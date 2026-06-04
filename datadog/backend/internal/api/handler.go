package api

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/auth"
	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/config"
	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/store"
)

const tokenTTL = 24 * time.Hour

type Handler struct {
	Store *store.Store
	Cfg   *config.Config
	Log   *slog.Logger
}

// Routes は dashboard(user=JWT) 経路を返す。ingest(machine=API key) / query / alert は
// Phase 3/4 でここに追加する。
func (h *Handler) Routes() http.Handler {
	r := chi.NewRouter()
	r.Get("/healthz", h.health)
	r.Post("/auth/register", h.register)
	r.Post("/auth/login", h.login)

	r.Group(func(pr chi.Router) {
		pr.Use(h.RequireJWT)
		pr.Get("/me", h.me)
	})
	return r
}

// ─── handlers ───────────────────────────────────────────────────────────────

func (h *Handler) health(w http.ResponseWriter, r *http.Request) {
	if err := h.Store.DB.PingContext(r.Context()); err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]any{"ok": false, "db": false})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

type credentials struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

func (h *Handler) register(w http.ResponseWriter, r *http.Request) {
	var c credentials
	if !decode(w, r, &c) {
		return
	}
	c.Email = strings.TrimSpace(c.Email)
	if c.Email == "" || len(c.Password) < 8 {
		http.Error(w, "email required and password must be >= 8 chars", http.StatusUnprocessableEntity)
		return
	}
	hash, err := auth.HashPassword(c.Password)
	if err != nil {
		h.serverError(w, "hash password", err)
		return
	}
	id, err := h.Store.CreateUser(r.Context(), c.Email, hash)
	if err != nil {
		if isDup(err) {
			http.Error(w, "email already registered", http.StatusConflict)
			return
		}
		h.serverError(w, "create user", err)
		return
	}
	h.issueToken(w, id)
}

func (h *Handler) login(w http.ResponseWriter, r *http.Request) {
	var c credentials
	if !decode(w, r, &c) {
		return
	}
	u, err := h.Store.UserByEmail(r.Context(), strings.TrimSpace(c.Email))
	if errors.Is(err, store.ErrNotFound) || (err == nil && !auth.CheckPassword(u.PasswordHash, c.Password)) {
		http.Error(w, "invalid credentials", http.StatusUnauthorized)
		return
	}
	if err != nil {
		h.serverError(w, "login lookup", err)
		return
	}
	h.issueToken(w, u.ID)
}

func (h *Handler) me(w http.ResponseWriter, r *http.Request) {
	id, _ := UserIDFrom(r.Context())
	u, err := h.Store.UserByID(r.Context(), id)
	if errors.Is(err, store.ErrNotFound) {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	if err != nil {
		h.serverError(w, "me lookup", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"id": u.ID, "email": u.Email})
}

// ─── middleware ──────────────────────────────────────────────────────────────

// RequireJWT は Authorization: Bearer <jwt> を検証し user_id を context に載せる。
func (h *Handler) RequireJWT(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		tok := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		if tok == "" || tok == r.Header.Get("Authorization") { // 接頭辞が無ければ未認証
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		claims, err := auth.ParseUserToken([]byte(h.Cfg.JWTSecret), tok)
		if err != nil {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r.WithContext(withUserID(r.Context(), claims.UserID)))
	})
}

// RequireAPIKey は ingest(machine) 経路用。X-API-Key を sha256 hash して照合する (Phase 3 で /ingest に適用)。
// config の固定 key と一致するか、DB の api_keys に存在すれば許可。
func (h *Handler) RequireAPIKey(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		key := r.Header.Get("X-API-Key")
		if key == "" {
			http.Error(w, "missing api key", http.StatusUnauthorized)
			return
		}
		hash := auth.HashAPIKey(key)
		if h.Cfg.IngestAPIKey != "" && auth.SameAPIKeyHash(hash, auth.HashAPIKey(h.Cfg.IngestAPIKey)) {
			next.ServeHTTP(w, r)
			return
		}
		if _, err := h.Store.APIKeyByHash(r.Context(), hash); err == nil {
			next.ServeHTTP(w, r)
			return
		}
		http.Error(w, "invalid api key", http.StatusUnauthorized)
	})
}

// ─── helpers ─────────────────────────────────────────────────────────────────

func (h *Handler) issueToken(w http.ResponseWriter, userID int64) {
	tok, err := auth.SignUserToken([]byte(h.Cfg.JWTSecret), userID, tokenTTL)
	if err != nil {
		h.serverError(w, "sign token", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"token": tok, "user_id": userID})
}

func (h *Handler) serverError(w http.ResponseWriter, msg string, err error) {
	if h.Log != nil {
		h.Log.Error(msg, slog.Any("err", err))
	}
	http.Error(w, "internal", http.StatusInternalServerError)
}

func decode(w http.ResponseWriter, r *http.Request, v any) bool {
	if err := json.NewDecoder(r.Body).Decode(v); err != nil {
		http.Error(w, "invalid JSON body", http.StatusBadRequest)
		return false
	}
	return true
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func isDup(err error) bool {
	return err != nil && strings.Contains(err.Error(), "Error 1062")
}
