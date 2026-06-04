package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	chicors "github.com/go-chi/cors"

	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/ai"
	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/alert"
	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/api"
	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/config"
	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/ingest"
	"github.com/hiratatomoaki/service-architecture-lab/datadog/backend/internal/store"
)

// Phase 2: config + DB + 認証(JWT/API key) + /healthz の最小サーバ。
// ingestion pipeline (Phase 3) / alert engine (Phase 4) / dashboard 用 query はこれから追加する。
func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	cfg, err := config.Load()
	if err != nil {
		log.Error("config load", slog.Any("err", err))
		os.Exit(1)
	}
	if err := cfg.MustValidate(); err != nil {
		log.Error("config invalid", slog.Any("err", err))
		os.Exit(1)
	}

	st, err := store.Open(cfg.DatabaseURL)
	if err != nil {
		log.Error("db open", slog.Any("err", err))
		os.Exit(1)
	}
	defer st.DB.Close()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	// ingestion パイプライン起動 (ADR 0001): worker pool + single-owner aggregator goroutine。
	pipe := ingest.NewPipeline(st, ingest.Options{
		IngestBuffer: cfg.IngestBufferSize,
		SampleBuffer: cfg.SampleBufferSize,
		Workers:      cfg.WorkerCount,
		WindowSec:    cfg.WindowSeconds,
		MaxSeries:    cfg.MaxSeries,
		Log:          log,
	})
	pipeDone := make(chan struct{})
	go func() { pipe.Run(ctx); close(pipeDone) }()

	// alert engine 起動 (ADR 0004): 周期評価 state machine。dynamic rule 用に ai-worker を配線
	// (URL 未設定なら nil interface = 静的閾値のみ)。
	var anomaly alert.AnomalyClient
	if cfg.AIWorkerURL != "" {
		anomaly = ai.NewClient(cfg.AIWorkerURL, cfg.AIInternalToken)
	}
	engine := alert.NewEngine(st, anomaly, cfg.WindowSeconds, cfg.EvalIntervalSec, log)
	engineDone := make(chan struct{})
	go func() { engine.Run(ctx); close(engineDone) }()

	h := &api.Handler{Store: st, Cfg: cfg, Pipeline: pipe, Log: log}

	root := chi.NewRouter()
	root.Use(middleware.RealIP, middleware.RequestID, middleware.Recoverer)
	root.Use(chicors.Handler(chicors.Options{
		AllowedOrigins:   []string{"http://localhost:*", "http://127.0.0.1:*"},
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Authorization", "Content-Type", "X-API-Key"},
		AllowCredentials: false,
	}))
	root.Group(func(r chi.Router) {
		r.Use(middleware.Timeout(30 * time.Second))
		r.Mount("/", h.Routes())
	})

	srv := &http.Server{Addr: cfg.Addr, Handler: root, ReadHeaderTimeout: 5 * time.Second}

	go func() {
		log.Info("listening", slog.String("addr", cfg.Addr))
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("listen", slog.Any("err", err))
			stop()
		}
	}()

	<-ctx.Done()
	log.Info("shutting down")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = srv.Shutdown(shutdownCtx)
	<-pipeDone   // aggregator の最終 flush を待つ
	<-engineDone // alert engine の停止を待つ
}
