package api

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/auth"
	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/config"
	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/ingest"
	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/store"
)

const tokenTTL = 24 * time.Hour

type Handler struct {
	Store    *store.Store
	Cfg      *config.Config
	Pipeline *ingest.Pipeline
	Log      *slog.Logger
}

// Routes は dashboard(user=JWT) 経路を返す。ingest(machine=API key) / query / alert は
// Phase 3/4 でここに追加する。
func (h *Handler) Routes() http.Handler {
	r := chi.NewRouter()
	r.Get("/healthz", h.health)
	r.Post("/auth/register", h.register)
	r.Post("/auth/login", h.login)

	// ingest (machine 経路 = API key, ADR 0004)
	r.Group(func(ir chi.Router) {
		ir.Use(h.RequireAPIKey)
		ir.Post("/ingest", h.ingest)
	})

	// dashboard (user 経路 = JWT)
	r.Group(func(pr chi.Router) {
		pr.Use(h.RequireJWT)
		pr.Get("/me", h.me)
		pr.Get("/query", h.query)
		pr.Get("/metrics", h.metrics)
		pr.Get("/stats", h.stats)
		pr.Get("/alerts/rules", h.listAlertRules)
		pr.Post("/alerts/rules", h.createAlertRule)
		pr.Get("/alerts/events", h.listAlertEvents)
	})
	return r
}

// ─── alert rules / events (ADR 0004) ─────────────────────────────────────────

type alertRuleReq struct {
	Name        string            `json:"name"`
	MetricName  string            `json:"metric_name"`
	TagMatchers map[string]string `json:"tag_matchers"`
	Comparator  string            `json:"comparator"` // gt / lt
	Threshold   float64           `json:"threshold"`
	WindowS     int               `json:"window_s"`
	ForS        int               `json:"for_s"`
	Agg         string            `json:"agg"`
	Dynamic     bool              `json:"dynamic"`
}

func (h *Handler) createAlertRule(w http.ResponseWriter, r *http.Request) {
	uid, _ := UserIDFrom(r.Context())
	var req alertRuleReq
	if !decode(w, r, &req) {
		return
	}
	if req.Name == "" || req.MetricName == "" {
		http.Error(w, "name and metric_name required", http.StatusUnprocessableEntity)
		return
	}
	if req.Comparator != "gt" && req.Comparator != "lt" {
		http.Error(w, "comparator must be gt or lt", http.StatusUnprocessableEntity)
		return
	}
	if req.Agg == "" {
		req.Agg = "avg"
	}
	matchers, _ := json.Marshal(req.TagMatchers)
	if req.TagMatchers == nil {
		matchers = []byte("{}")
	}
	id, err := h.Store.CreateAlertRule(r.Context(), store.AlertRule{
		OwnerID: uid, Name: req.Name, MetricName: req.MetricName, TagMatchers: string(matchers),
		Comparator: req.Comparator, Threshold: req.Threshold, WindowS: req.WindowS,
		ForS: req.ForS, Agg: req.Agg, Dynamic: req.Dynamic, Enabled: true,
	})
	if err != nil {
		h.serverError(w, "create alert rule", err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"id": id})
}

func (h *Handler) listAlertRules(w http.ResponseWriter, r *http.Request) {
	rules, err := h.Store.ListAlertRules(r.Context())
	if err != nil {
		h.serverError(w, "list alert rules", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"rules": rules})
}

func (h *Handler) listAlertEvents(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	events, err := h.Store.RecentAlertEvents(r.Context(), limit)
	if err != nil {
		h.serverError(w, "list alert events", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"events": events})
}

// ─── ingest (ADR 0001/0002) ──────────────────────────────────────────────────

type ingestReq struct {
	Samples []ingest.Sample `json:"samples"`
}

func (h *Handler) ingest(w http.ResponseWriter, r *http.Request) {
	var req ingestReq
	if !decode(w, r, &req) {
		return
	}
	accepted := 0
	for _, s := range req.Samples {
		if s.Type == "" {
			s.Type = "gauge"
		}
		if h.Pipeline.Enqueue(s) {
			accepted++
		}
	}
	// fire-and-forget: drop しても 202 (ADR 0002)。dropped は /stats で可視化。
	writeJSON(w, http.StatusAccepted, map[string]any{"accepted": accepted, "received": len(req.Samples)})
}

// ─── query / metrics / stats (ADR 0003) ──────────────────────────────────────

func (h *Handler) query(w http.ResponseWriter, r *http.Request) {
	metric := r.URL.Query().Get("metric")
	if metric == "" {
		http.Error(w, "metric required", http.StatusUnprocessableEntity)
		return
	}
	to := parseTimeOr(r.URL.Query().Get("to"), time.Now())
	from := parseTimeOr(r.URL.Query().Get("from"), to.Add(-time.Hour))
	res := h.Cfg.WindowSeconds

	all, err := h.Store.ListSeries(r.Context(), metric)
	if err != nil {
		h.serverError(w, "list series", err)
		return
	}
	out := make([]map[string]any, 0, len(all))
	for _, se := range all {
		rollups, err := h.Store.QueryRollups(r.Context(), se.SeriesKey, from, to, res)
		if err != nil {
			h.serverError(w, "query rollups", err)
			return
		}
		points := make([]map[string]any, 0, len(rollups))
		for _, rl := range rollups {
			avg := 0.0
			if rl.Count > 0 {
				avg = rl.Sum / float64(rl.Count)
			}
			points = append(points, map[string]any{
				"ts": rl.BucketTS.UTC().Format(time.RFC3339), "count": rl.Count,
				"sum": rl.Sum, "min": rl.Min, "max": rl.Max, "last": rl.Last, "avg": avg,
			})
		}
		out = append(out, map[string]any{"series_key": se.SeriesKey, "tags": rawJSON(se.Tags), "points": points})
	}
	writeJSON(w, http.StatusOK, map[string]any{"metric": metric, "resolution_s": res, "series": out})
}

func (h *Handler) metrics(w http.ResponseWriter, r *http.Request) {
	all, err := h.Store.ListSeries(r.Context(), r.URL.Query().Get("metric"))
	if err != nil {
		h.serverError(w, "list series", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"count": len(all), "series": all})
}

func (h *Handler) stats(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, h.Pipeline.Counters.Snapshot())
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

// parseTimeOr は RFC3339 か unix 秒を解釈し、失敗時は def を返す。
func parseTimeOr(s string, def time.Time) time.Time {
	if s == "" {
		return def
	}
	if t, err := time.Parse(time.RFC3339, s); err == nil {
		return t
	}
	if sec, err := strconv.ParseInt(s, 10, 64); err == nil {
		return time.Unix(sec, 0)
	}
	return def
}

// rawJSON は DB の JSON 列文字列を二重エンコードせず埋め込む。
func rawJSON(s string) json.RawMessage {
	if s == "" {
		return json.RawMessage("null")
	}
	return json.RawMessage(s)
}
