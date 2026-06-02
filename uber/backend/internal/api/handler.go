// Package api は HTTP handler (chi.Router) を集約する。
// Phase 4-3 では auth (register / login / me) のみ。trip 系 endpoint は Phase 4-1。
package api

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-sql-driver/mysql"

	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/ai"
	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/auth"
	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/dispatch"
	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/store"
)

const mysqlErrDuplicate = 1062

const jwtTTL = 7 * 24 * time.Hour

type Handler struct {
	Log          *slog.Logger
	Store        *store.Store
	JWTSecret    []byte
	Registry     *dispatch.CellRegistry // optional, trip エンドポイント用 (Phase 4-1 で注入)
	AI           *ai.Client             // optional, ETA / demand-forecast 用 (Phase 4-2 で注入); nil/未設定なら degrade
	H3Resolution int                    // 9 by default (ADR 0001)
}

func NewHandler(log *slog.Logger, st *store.Store, jwtSecret []byte) *Handler {
	return &Handler{Log: log, Store: st, JWTSecret: jwtSecret, H3Resolution: 9}
}

func (h *Handler) Routes() chi.Router {
	r := chi.NewRouter()
	r.Post("/auth/register", h.PostRegister)
	r.Post("/auth/login", h.PostLogin)

	r.Group(func(r chi.Router) {
		r.Use(h.AuthMiddleware)
		r.Get("/me", h.GetMe)
		r.Post("/trips", h.PostTrip)
		r.Get("/trips/{id}", h.GetTrip)
		r.Post("/trips/{id}/cancel", h.PostTripCancel)
		r.Get("/demand", h.GetDemandForecast)
	})
	return r
}

// ---- helpers ----

func jsonWrite(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func jsonError(w http.ResponseWriter, status int, msg string) {
	jsonWrite(w, status, map[string]string{"error": msg})
}

func readJSON[T any](r *http.Request, out *T) error {
	defer r.Body.Close()
	dec := json.NewDecoder(io.LimitReader(r.Body, 1<<20))
	dec.DisallowUnknownFields()
	return dec.Decode(out)
}

func isDuplicate(err error) bool {
	var me *mysql.MySQLError
	if errors.As(err, &me) && me.Number == mysqlErrDuplicate {
		return true
	}
	return false
}

// ---- middleware ----

func (h *Handler) AuthMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hdr := strings.TrimSpace(r.Header.Get("Authorization"))
		if !strings.HasPrefix(hdr, "Bearer ") {
			jsonError(w, http.StatusUnauthorized, "missing or invalid Authorization")
			return
		}
		raw := strings.TrimSpace(strings.TrimPrefix(hdr, "Bearer "))
		cl, err := auth.ParseUserToken(h.JWTSecret, raw)
		if err != nil {
			jsonError(w, http.StatusUnauthorized, "invalid token")
			return
		}
		ctx := context.WithValue(r.Context(), userIDKey, cl.UserID)
		ctx = context.WithValue(ctx, roleKey, cl.Role)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func (h *Handler) requireUID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	uid, ok := UserIDFromContext(r.Context())
	if !ok || uid <= 0 {
		jsonError(w, http.StatusUnauthorized, "missing user context")
		return 0, false
	}
	return uid, true
}

// ---- auth endpoints ----

type registerBody struct {
	Email       string `json:"email"`
	Password    string `json:"password"`
	Role        string `json:"role"`
	DisplayName string `json:"display_name"`
}

func (h *Handler) PostRegister(w http.ResponseWriter, r *http.Request) {
	var body registerBody
	if err := readJSON(r, &body); err != nil {
		jsonError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	body.Email = strings.TrimSpace(strings.ToLower(body.Email))
	body.DisplayName = strings.TrimSpace(body.DisplayName)
	body.Role = strings.ToLower(strings.TrimSpace(body.Role))

	if body.Email == "" || !strings.Contains(body.Email, "@") {
		jsonError(w, http.StatusBadRequest, "valid email required")
		return
	}
	if len(body.Password) < 8 {
		jsonError(w, http.StatusBadRequest, "password min 8 chars")
		return
	}
	if body.DisplayName == "" {
		jsonError(w, http.StatusBadRequest, "display_name required")
		return
	}
	if body.Role != string(store.RoleRider) && body.Role != string(store.RoleDriver) {
		jsonError(w, http.StatusBadRequest, "role must be 'rider' or 'driver'")
		return
	}

	hash, err := auth.HashPassword(body.Password)
	if err != nil {
		h.Log.Error("hash password", slog.Any("err", err))
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}

	id, err := h.Store.CreateUser(r.Context(), body.Email, hash, store.Role(body.Role), body.DisplayName)
	if err != nil {
		if isDuplicate(err) {
			jsonError(w, http.StatusConflict, "email taken")
			return
		}
		h.Log.Error("create user", slog.Any("err", err))
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}

	// driver role なら drivers 行も作る (offline 状態で)。
	// 厳密には 1 Tx にまとめるべきだが、user-only / driver の 2 段で済ませる方が単純。
	// 失敗時の整合性は手動運用で吸収する (Phase 4-3 の learning scope はここまで)。
	if body.Role == string(store.RoleDriver) {
		if err := h.Store.CreateDriver(r.Context(), id); err != nil {
			h.Log.Error("create driver", slog.Any("err", err))
			jsonError(w, http.StatusInternalServerError, "internal error")
			return
		}
	}

	token, err := auth.SignUserToken(h.JWTSecret, id, body.Role, jwtTTL)
	if err != nil {
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}

	u, err := h.Store.UserByID(r.Context(), id)
	if err != nil {
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	jsonWrite(w, http.StatusCreated, map[string]any{
		"token": token,
		"user":  userView(u),
	})
}

type loginBody struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

func (h *Handler) PostLogin(w http.ResponseWriter, r *http.Request) {
	var body loginBody
	if err := readJSON(r, &body); err != nil {
		jsonError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	body.Email = strings.TrimSpace(strings.ToLower(body.Email))

	u, err := h.Store.UserByEmail(r.Context(), body.Email)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			jsonError(w, http.StatusUnauthorized, "invalid credentials")
			return
		}
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	if !auth.CheckPassword(u.PasswordHash, body.Password) {
		jsonError(w, http.StatusUnauthorized, "invalid credentials")
		return
	}

	token, err := auth.SignUserToken(h.JWTSecret, u.ID, string(u.Role), jwtTTL)
	if err != nil {
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	jsonWrite(w, http.StatusOK, map[string]any{
		"token": token,
		"user":  userView(u),
	})
}

func (h *Handler) GetMe(w http.ResponseWriter, r *http.Request) {
	uid, ok := h.requireUID(w, r)
	if !ok {
		return
	}
	u, err := h.Store.UserByID(r.Context(), uid)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			jsonError(w, http.StatusNotFound, "user not found")
			return
		}
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	jsonWrite(w, http.StatusOK, map[string]any{
		"user": userView(u),
	})
}

func userView(u *store.User) map[string]any {
	return map[string]any{
		"id":           u.ID,
		"email":        u.Email,
		"role":         u.Role,
		"display_name": u.DisplayName,
		"created_at":   u.CreatedAt.UTC().Format(time.RFC3339Nano),
	}
}
