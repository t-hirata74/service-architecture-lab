package main

import (
	"context"
	"database/sql"
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

	"github.com/hiratatomoaki/service-architecture-lab/discord/backend/internal/api"
	"github.com/hiratatomoaki/service-architecture-lab/discord/backend/internal/config"
	"github.com/hiratatomoaki/service-architecture-lab/discord/backend/internal/gateway"
	"github.com/hiratatomoaki/service-architecture-lab/discord/backend/internal/store"
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

	hubCtx, hubCancel := context.WithCancel(context.Background())
	defer hubCancel()
	hbInterval := time.Duration(cfg.HeartbeatIntervalMs) * time.Millisecond
	registry := gateway.NewRegistry(hubCtx, hbInterval, log)

	gw := &gateway.Service{
		Log:               log,
		Store:             st,
		JWTSecret:         []byte(cfg.JWTSecret),
		Registry:          registry,
		HeartbeatInterval: hbInterval,
		AllowedOrigins:    []string{"http://localhost:3055"},
	}

	h := api.NewHandler(log, st, []byte(cfg.JWTSecret), cfg.AIWorkerURL, cfg.AIInternalToken, registry)

	root := chi.NewRouter()
	root.Use(middleware.RealIP)
	root.Use(middleware.RequestID)
	root.Use(middleware.Recoverer)
	root.Use(chicors.Handler(chicors.Options{
		AllowedOrigins:   []string{"http://localhost:3055"},
		AllowedMethods:   []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type"},
		AllowCredentials: true,
	}))

	// /gateway must NOT be wrapped by middleware.Timeout — long-lived WS.
	root.Get("/gateway", gw.HandleGateway)

	root.Group(func(r chi.Router) {
		r.Use(middleware.Timeout(120 * time.Second))
		r.Mount("/", h.Routes())
	})

	srv := &http.Server{
		Addr:              cfg.Addr,
		Handler:           root,
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		log.Info("listening", slog.String("addr", cfg.Addr),
			slog.Int("heartbeat_ms", cfg.HeartbeatIntervalMs))
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
	hubCancel() // stop all Hub goroutines
	log.Info("shutdown complete")
}

// openDBWithBackoff parses the MySQL DSN, disables multiStatements for the pooled connection,
// and retries Dial until Docker MySQL is ready.
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
