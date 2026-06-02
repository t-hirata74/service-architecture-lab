// Package main は uber backend のエントリポイント。
// Phase 4-1 で REST trip endpoints + WS gateway + matcher 配線まで載っている。
package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	chicors "github.com/go-chi/cors"
	"github.com/go-sql-driver/mysql"

	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/ai"
	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/api"
	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/config"
	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/dispatch"
	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/store"
	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/ws"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		panic(err)
	}
	if err := cfg.MustValidate(); err != nil {
		panic(err)
	}

	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))

	db, err := openDBWithBackoff(cfg.DatabaseURL, 15, time.Second)
	if err != nil {
		log.Error("database", slog.Any("err", err))
		os.Exit(1)
	}
	db.SetMaxOpenConns(20)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)
	defer db.Close()

	st := &store.Store{DB: db}

	// matcher 配線 (ADR 0003)
	matcherCtx, matcherCancel := context.WithCancel(context.Background())
	defer matcherCancel()
	acceptor := &dispatch.StoreAcceptor{Store: st}
	registry := dispatch.NewCellRegistry(matcherCtx, dispatch.DefaultMatcherConfig(), log, acceptor)

	// ai-worker クライアント (ADR 0004)。AI_WORKER_URL 未設定なら Enabled()==false で degrade。
	aiClient := ai.NewClient(cfg.AIWorkerURL, cfg.AIInternalToken)
	if aiClient.Enabled() {
		log.Info("ai-worker configured", slog.String("url", cfg.AIWorkerURL))
	} else {
		log.Info("ai-worker not configured; ETA / demand will degrade")
	}

	h := api.NewHandler(log, st, []byte(cfg.JWTSecret))
	h.Registry = registry
	h.AI = aiClient
	h.H3Resolution = cfg.H3Resolution

	gw := &ws.Service{
		Log: log, Store: st, JWTSecret: []byte(cfg.JWTSecret),
		Registry: registry, H3Resolution: cfg.H3Resolution,
		AllowedOrigins: []string{"http://localhost:3115"},
	}

	root := chi.NewRouter()
	root.Use(middleware.RealIP)
	root.Use(middleware.RequestID)
	root.Use(middleware.Recoverer)
	root.Use(chicors.Handler(chicors.Options{
		AllowedOrigins:   []string{"http://localhost:3115"},
		AllowedMethods:   []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type"},
		AllowCredentials: true,
	}))

	// /ws は long-lived なので middleware.Timeout の外に置く
	root.Get("/ws", gw.HandleWS)

	root.Group(func(r chi.Router) {
		r.Use(middleware.Timeout(120 * time.Second))
		r.Get("/healthz", healthz(st))
		r.Mount("/", h.Routes())
	})

	srv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           root,
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		log.Info("listening",
			slog.String("addr", cfg.Addr),
			slog.Int("h3_resolution", cfg.H3Resolution))
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Error("server exit", slog.Any("err", err))
			os.Exit(1)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = srv.Shutdown(ctx)
	matcherCancel() // matcher goroutines 全停止
	log.Info("shutdown complete")
}

func healthz(st *store.Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		status := "ok"
		dbOK := true
		if err := st.Ping(); err != nil {
			status = "degraded"
			dbOK = false
		}
		w.Header().Set("Content-Type", "application/json")
		if !dbOK {
			w.WriteHeader(http.StatusServiceUnavailable)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"status": status,
			"db":     dbOK,
		})
	}
}

// openDBWithBackoff は discord backend と同形 (再起動直後の MySQL 起動待ち)。
func openDBWithBackoff(raw string, tries int, wait time.Duration) (*sql.DB, error) {
	mc, err := mysql.ParseDSN(raw)
	if err != nil {
		return nil, err
	}
	mc.MultiStatements = false
	dsn := mc.FormatDSN()

	var db *sql.DB
	var lastErr error
	for i := 0; i < tries; i++ {
		db, lastErr = sql.Open("mysql", dsn)
		if lastErr != nil {
			time.Sleep(wait)
			continue
		}
		lastErr = db.Ping()
		if lastErr != nil {
			_ = db.Close()
			time.Sleep(wait)
			continue
		}
		return db, nil
	}
	return nil, lastErr
}
