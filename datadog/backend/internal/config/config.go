package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

// Config は env から読む。pipeline / aggregator のチューニング knob も含む (ADR 0001/0002)。
type Config struct {
	Addr            string
	DatabaseURL     string
	JWTSecret       string
	IngestAPIKey    string // /ingest の X-API-Key (machine 経路、ADR 0004)。空なら DB の api_keys を使う想定
	AIWorkerURL     string
	AIInternalToken string

	// pipeline tuning (ADR 0001/0002)
	IngestBufferSize int // bounded ingest chan のサイズ (満杯=load shedding)
	SampleBufferSize int // worker → aggregator chan のサイズ
	WorkerCount      int // parse/route worker pool 数
	WindowSeconds    int // rollup 固定窓 (resolution)
	MaxSeries        int // cardinality 上限 (超過=新規 series drop)
	RetentionWindows int // in-memory ring が保持する窓数
	EvalIntervalSec  int // alert eval loop の tick (ADR 0004)
}

func Load() (*Config, error) {
	return &Config{
		Addr:             envStr("HTTP_ADDR", ":3130"),
		DatabaseURL:      envStr("DATABASE_URL", "datadog:datadog@tcp(127.0.0.1:3329)/datadog_development?parseTime=true&multiStatements=true"),
		JWTSecret:        envStr("JWT_SECRET", "dev-secret-do-not-use-in-prod"),
		IngestAPIKey:     envStr("INGEST_API_KEY", "dev-ingest-key"),
		AIWorkerURL:      strings.TrimSpace(os.Getenv("AI_WORKER_URL")),
		AIInternalToken:  envStr("AI_INTERNAL_TOKEN", "dev-internal-token"),
		IngestBufferSize: envInt("INGEST_BUFFER_SIZE", 4096, 1),
		SampleBufferSize: envInt("SAMPLE_BUFFER_SIZE", 4096, 1),
		WorkerCount:      envInt("WORKER_COUNT", 4, 1),
		WindowSeconds:    envInt("WINDOW_SECONDS", 10, 1),
		MaxSeries:        envInt("MAX_SERIES", 10000, 1),
		RetentionWindows: envInt("RETENTION_WINDOWS", 60, 1),
		EvalIntervalSec:  envInt("EVAL_INTERVAL_SEC", 10, 1),
	}, nil
}

func (c *Config) MustValidate() error {
	if len(c.JWTSecret) < 8 {
		return fmt.Errorf("JWT_SECRET must be at least 8 characters")
	}
	if c.IngestAPIKey == "" {
		return fmt.Errorf("INGEST_API_KEY must not be empty")
	}
	return nil
}

func envStr(key, def string) string {
	if v := strings.TrimSpace(os.Getenv(key)); v != "" {
		return v
	}
	return def
}

func envInt(key string, def, min int) int {
	if s := strings.TrimSpace(os.Getenv(key)); s != "" {
		if v, err := strconv.Atoi(s); err == nil && v >= min {
			return v
		}
	}
	return def
}
