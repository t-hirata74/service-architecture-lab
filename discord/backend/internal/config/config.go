package config

import (
	"fmt"
	"os"
	"strings"
)

type Config struct {
	Addr         string
	DatabaseURL  string
	JWTSecret    string
	AIWorkerURL  string
}

func Load() (*Config, error) {
	dsn := strings.TrimSpace(os.Getenv("DATABASE_URL"))
	if dsn == "" {
		dsn = "discord:discord@tcp(127.0.0.1:3312)/discord_development?parseTime=true&multiStatements=true"
	}
	sec := strings.TrimSpace(os.Getenv("JWT_SECRET"))
	if sec == "" {
		sec = "dev-secret-do-not-use-in-prod"
	}
	addr := strings.TrimSpace(os.Getenv("HTTP_ADDR"))
	if addr == "" {
		addr = ":3060"
	}
	ai := strings.TrimSpace(os.Getenv("AI_WORKER_URL"))
	return &Config{
		Addr:        addr,
		DatabaseURL: dsn,
		JWTSecret:   sec,
		AIWorkerURL: ai,
	}, nil
}

func (c *Config) MustValidate() error {
	if len(c.JWTSecret) < 8 {
		return fmt.Errorf("JWT_SECRET must be at least 8 characters")
	}
	return nil
}
