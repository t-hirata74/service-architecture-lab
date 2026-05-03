package api

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/hiratatomoaki/service-architecture-lab/discord/backend/internal/auth"
	"github.com/hiratatomoaki/service-architecture-lab/discord/backend/internal/store"
)

const jwtTTL = 7 * 24 * time.Hour

type Handler struct {
	Log       *slog.Logger
	Store     *store.Store
	JWTSecret []byte
	AIWorker  string
}

func NewHandler(log *slog.Logger, st *store.Store, jwtSecret []byte, aiWorker string) *Handler {
	return &Handler{Log: log, Store: st, JWTSecret: jwtSecret, AIWorker: strings.TrimSuffix(aiWorker, "/")}
}

func (h *Handler) Routes() chi.Router {
	r := chi.NewRouter()
	r.Post("/auth/register", h.PostRegister)
	r.Post("/auth/login", h.PostLogin)
	r.Get("/health", h.Health)

	r.Group(func(r chi.Router) {
		r.Use(h.AuthMiddleware)
		r.Get("/me", h.GetMe)
		r.Get("/guilds", h.GetGuilds)
		r.Post("/guilds", h.PostGuild)

		r.Post("/guilds/{guildID}/members", h.PostGuildMember)
		r.Get("/guilds/{guildID}/channels", h.GetGuildChannels)
		r.Post("/guilds/{guildID}/channels", h.PostGuildChannel)

		r.Get("/channels/{channelID}/messages", h.GetChannelMessages)
		r.Post("/channels/{channelID}/messages", h.PostChannelMessage)
		r.Post("/channels/{channelID}/summarize", h.PostChannelSummarize)
	})
	return r
}

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

type registerBody struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

func (h *Handler) PostRegister(w http.ResponseWriter, r *http.Request) {
	var body registerBody
	if err := readJSON(r, &body); err != nil {
		jsonError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	body.Username = strings.TrimSpace(body.Username)
	if body.Username == "" || len(body.Password) < 8 {
		jsonError(w, http.StatusBadRequest, "username required and password min 8 chars")
		return
	}
	hash, err := auth.HashPassword(body.Password)
	if err != nil {
		h.Log.Error("hash password", slog.Any("err", err))
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	id, err := h.Store.CreateUser(r.Context(), body.Username, hash)
	if err != nil {
		if isDuplicate(err) {
			jsonError(w, http.StatusConflict, "username taken")
			return
		}
		h.Log.Error("create user", slog.Any("err", err))
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	token, err := auth.SignUserToken(h.JWTSecret, id, jwtTTL)
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
		"user": map[string]any{
			"id": u.ID, "username": u.Username, "created_at": u.CreatedAt.UTC().Format(time.RFC3339Nano),
		},
	})
}

func (h *Handler) PostLogin(w http.ResponseWriter, r *http.Request) {
	var body registerBody
	if err := readJSON(r, &body); err != nil {
		jsonError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	body.Username = strings.TrimSpace(body.Username)
	u, err := h.Store.UserByUsername(r.Context(), body.Username)
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
	token, err := auth.SignUserToken(h.JWTSecret, u.ID, jwtTTL)
	if err != nil {
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	jsonWrite(w, http.StatusOK, map[string]any{
		"token": token,
		"user": map[string]any{
			"id": u.ID, "username": u.Username, "created_at": u.CreatedAt.UTC().Format(time.RFC3339Nano),
		},
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
		"user": map[string]any{
			"id": u.ID, "username": u.Username, "created_at": u.CreatedAt.UTC().Format(time.RFC3339Nano),
		},
	})
}

func (h *Handler) GetGuilds(w http.ResponseWriter, r *http.Request) {
	uid, ok := h.requireUID(w, r)
	if !ok {
		return
	}
	list, err := h.Store.GuildsForUser(r.Context(), uid)
	if err != nil {
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	out := make([]map[string]any, 0, len(list))
	for _, g := range list {
		out = append(out, map[string]any{
			"id": g.ID, "name": g.Name, "owner_id": g.OwnerID,
			"created_at": g.CreatedAt.UTC().Format(time.RFC3339Nano),
		})
	}
	jsonWrite(w, http.StatusOK, map[string]any{"guilds": out})
}

type guildCreateBody struct {
	Name string `json:"name"`
}

func (h *Handler) PostGuild(w http.ResponseWriter, r *http.Request) {
	uid, ok := h.requireUID(w, r)
	if !ok {
		return
	}
	var body guildCreateBody
	if err := readJSON(r, &body); err != nil {
		jsonError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	body.Name = strings.TrimSpace(body.Name)
	if body.Name == "" {
		jsonError(w, http.StatusBadRequest, "name required")
		return
	}
	ctx := r.Context()
	gid, err := h.Store.CreateGuild(ctx, body.Name, uid)
	if err != nil {
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	if err := h.Store.CreateMembership(ctx, gid, uid, "owner"); err != nil {
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	g, err := h.Store.GuildByID(ctx, gid)
	if err != nil {
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	jsonWrite(w, http.StatusCreated, map[string]any{
		"guild": map[string]any{
			"id": g.ID, "name": g.Name, "owner_id": g.OwnerID,
			"created_at": g.CreatedAt.UTC().Format(time.RFC3339Nano),
		},
	})
}

func parseID(w http.ResponseWriter, param string) (int64, bool) {
	id, err := strconv.ParseInt(param, 10, 64)
	if err != nil || id <= 0 {
		jsonError(w, http.StatusBadRequest, "invalid id")
		return 0, false
	}
	return id, true
}

func (h *Handler) PostGuildMember(w http.ResponseWriter, r *http.Request) {
	uid, ok := h.requireUID(w, r)
	if !ok {
		return
	}
	guildID, ok := parseID(w, chi.URLParam(r, "guildID"))
	if !ok {
		return
	}
	ctx := r.Context()
	if _, err := h.Store.GuildByID(ctx, guildID); err != nil {
		if errors.Is(err, store.ErrNotFound) {
			jsonError(w, http.StatusNotFound, "guild not found")
			return
		}
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	if _, err := h.Store.Membership(ctx, guildID, uid); err == nil {
		jsonError(w, http.StatusConflict, "already a member")
		return
	} else if !errors.Is(err, store.ErrNotFound) {
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	if err := h.Store.CreateMembership(ctx, guildID, uid, "member"); err != nil {
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	m, err := h.Store.Membership(ctx, guildID, uid)
	if err != nil {
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	jsonWrite(w, http.StatusCreated, map[string]any{
		"membership": map[string]any{
			"guild_id": m.GuildID, "user_id": m.UserID, "role": m.Role,
			"joined_at": m.JoinedAt.UTC().Format(time.RFC3339Nano),
		},
	})
}

func (h *Handler) requireGuildMember(w http.ResponseWriter, r *http.Request, guildID int64, userID int64) (*store.Membership, bool) {
	m, err := h.Store.Membership(r.Context(), guildID, userID)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			jsonError(w, http.StatusForbidden, "not a member of this guild")
			return nil, false
		}
		jsonError(w, http.StatusInternalServerError, "internal error")
		return nil, false
	}
	return m, true
}

func (h *Handler) GetGuildChannels(w http.ResponseWriter, r *http.Request) {
	uid, ok := h.requireUID(w, r)
	if !ok {
		return
	}
	guildID, ok := parseID(w, chi.URLParam(r, "guildID"))
	if !ok {
		return
	}
	if _, ok := h.requireGuildMember(w, r, guildID, uid); !ok {
		return
	}
	list, err := h.Store.ChannelsByGuild(r.Context(), guildID)
	if err != nil {
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	out := make([]map[string]any, 0, len(list))
	for _, c := range list {
		out = append(out, map[string]any{
			"id": c.ID, "guild_id": c.GuildID, "name": c.Name,
			"created_at": c.CreatedAt.UTC().Format(time.RFC3339Nano),
		})
	}
	jsonWrite(w, http.StatusOK, map[string]any{"channels": out})
}

type channelBody struct {
	Name string `json:"name"`
}

func (h *Handler) PostGuildChannel(w http.ResponseWriter, r *http.Request) {
	uid, ok := h.requireUID(w, r)
	if !ok {
		return
	}
	guildID, ok := parseID(w, chi.URLParam(r, "guildID"))
	if !ok {
		return
	}
	if _, ok := h.requireGuildMember(w, r, guildID, uid); !ok {
		return
	}
	var body channelBody
	if err := readJSON(r, &body); err != nil {
		jsonError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	body.Name = strings.TrimSpace(body.Name)
	if body.Name == "" {
		jsonError(w, http.StatusBadRequest, "name required")
		return
	}
	ctx := r.Context()
	cid, err := h.Store.CreateChannel(ctx, guildID, body.Name)
	if err != nil {
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	ch, err := h.Store.ChannelByID(ctx, cid)
	if err != nil {
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	jsonWrite(w, http.StatusCreated, map[string]any{
		"channel": map[string]any{
			"id": ch.ID, "guild_id": ch.GuildID, "name": ch.Name,
			"created_at": ch.CreatedAt.UTC().Format(time.RFC3339Nano),
		},
	})
}

func (h *Handler) requireChannelGuildMember(w http.ResponseWriter, r *http.Request, channelID int64, userID int64) (*store.Channel, bool) {
	ch, err := h.Store.ChannelByID(r.Context(), channelID)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			jsonError(w, http.StatusNotFound, "channel not found")
			return nil, false
		}
		jsonError(w, http.StatusInternalServerError, "internal error")
		return nil, false
	}
	if _, ok := h.requireGuildMember(w, r, ch.GuildID, userID); !ok {
		return nil, false
	}
	return ch, true
}

func (h *Handler) GetChannelMessages(w http.ResponseWriter, r *http.Request) {
	uid, ok := h.requireUID(w, r)
	if !ok {
		return
	}
	chID, ok := parseID(w, chi.URLParam(r, "channelID"))
	if !ok {
		return
	}
	if _, ok := h.requireChannelGuildMember(w, r, chID, uid); !ok {
		return
	}
	limit := 50
	if s := strings.TrimSpace(r.URL.Query().Get("limit")); s != "" {
		if v, err := strconv.Atoi(s); err == nil && v > 0 && v <= 100 {
			limit = v
		}
	}
	var before *int64
	if s := strings.TrimSpace(r.URL.Query().Get("before")); s != "" {
		v, err := strconv.ParseInt(s, 10, 64)
		if err != nil || v <= 0 {
			jsonError(w, http.StatusBadRequest, "invalid before cursor")
			return
		}
		before = &v
	}
	msgs, err := h.Store.MessagesForChannel(r.Context(), chID, before, limit)
	if err != nil {
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	out := make([]map[string]any, 0, len(msgs))
	var nextBefore *int64
	for i, m := range msgs {
		out = append(out, map[string]any{
			"id": m.ID, "channel_id": m.ChannelID, "user_id": m.UserID, "body": m.Body,
			"author_username": m.AuthorUsername,
			"created_at": m.CreatedAt.UTC().Format(time.RFC3339Nano),
		})
		if i == len(msgs)-1 {
			id := m.ID
			nextBefore = &id
		}
	}
	resp := map[string]any{"messages": out, "limit": limit}
	if len(msgs) == limit && len(msgs) > 0 {
		resp["next_before"] = *nextBefore
		resp["has_more"] = true
	} else {
		resp["has_more"] = false
	}
	jsonWrite(w, http.StatusOK, resp)
}

type messageBody struct {
	Body string `json:"body"`
}

func (h *Handler) PostChannelMessage(w http.ResponseWriter, r *http.Request) {
	uid, ok := h.requireUID(w, r)
	if !ok {
		return
	}
	chID, ok := parseID(w, chi.URLParam(r, "channelID"))
	if !ok {
		return
	}
	if _, ok := h.requireChannelGuildMember(w, r, chID, uid); !ok {
		return
	}
	var body messageBody
	if err := readJSON(r, &body); err != nil {
		jsonError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	body.Body = strings.TrimSpace(body.Body)
	if body.Body == "" {
		jsonError(w, http.StatusBadRequest, "body required")
		return
	}
	ctx := r.Context()
	mid, err := h.Store.CreateMessage(ctx, chID, uid, body.Body)
	if err != nil {
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	m, err := h.Store.MessageByID(ctx, mid)
	if err != nil {
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	jsonWrite(w, http.StatusCreated, map[string]any{
		"message": map[string]any{
			"id": m.ID, "channel_id": m.ChannelID, "user_id": m.UserID, "body": m.Body,
			"author_username": m.AuthorUsername,
			"created_at": m.CreatedAt.UTC().Format(time.RFC3339Nano),
		},
	})
}

func (h *Handler) PostChannelSummarize(w http.ResponseWriter, r *http.Request) {
	uid, ok := h.requireUID(w, r)
	if !ok {
		return
	}
	chID, ok := parseID(w, chi.URLParam(r, "channelID"))
	if !ok {
		return
	}
	if _, ok := h.requireChannelGuildMember(w, r, chID, uid); !ok {
		return
	}
	snippets, err := h.Store.RecentMessageSnippets(r.Context(), chID, 20)
	if err != nil {
		jsonError(w, http.StatusInternalServerError, "internal error")
		return
	}
	summary, degraded := h.callSummarize(r.Context(), snippets)
	jsonWrite(w, http.StatusOK, map[string]any{
		"summary":   summary,
		"degraded":  degraded,
		"messages_used": len(snippets),
	})
}

func (h *Handler) callSummarize(ctx context.Context, snippets []store.MessageSnippet) (summary string, degraded bool) {
	if h.AIWorker == "" || len(snippets) == 0 {
		return "", true
	}
	payload := map[string]any{"messages": snippets}
	buf, err := json.Marshal(payload)
	if err != nil {
		return "", true
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, h.AIWorker+"/summarize", bytes.NewReader(buf))
	if err != nil {
		return "", true
	}
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Do(req)
	if err != nil || resp.StatusCode >= 300 {
		if resp != nil {
			resp.Body.Close()
		}
		return "", true
	}
	defer resp.Body.Close()
	var parsed struct {
		Summary string `json:"summary"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&parsed); err != nil {
		return "", true
	}
	return parsed.Summary, false
}

func (h *Handler) Health(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	status := map[string]string{"database": "down", "ai_worker": "skipped"}
	dbOK := func() bool {
		if err := h.Store.DB.PingContext(ctx); err != nil {
			return false
		}
		return true
	}()
	if dbOK {
		status["database"] = "up"
	}
	if h.AIWorker != "" {
		reqCtx, cancel := context.WithTimeout(ctx, 1500*time.Millisecond)
		defer cancel()
		req, err := http.NewRequestWithContext(reqCtx, http.MethodGet, h.AIWorker+"/health", nil)
		if err != nil {
			status["ai_worker"] = "down"
		} else {
			resp, err := http.DefaultClient.Do(req)
			if err != nil || resp.StatusCode >= 300 {
				if resp != nil {
					resp.Body.Close()
				}
				status["ai_worker"] = "down"
			} else {
				resp.Body.Close()
				status["ai_worker"] = "up"
			}
		}
	}

	code := http.StatusOK
	msg := map[string]any{"ok": dbOK, "checks": status}
	if !dbOK {
		code = http.StatusServiceUnavailable
		msg["ok"] = false
	}
	jsonWrite(w, code, msg)
}

func isDuplicate(err error) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "duplicate") || strings.Contains(msg, "unique")
}
