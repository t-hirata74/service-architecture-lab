package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	Addr            string
	DatabaseURL     string
	JWTSecret       string
	AIWorkerURL     string
	AIInternalToken string
	H3Resolution    int
}

func Load() (*Config, error) {
	dsn := strings.TrimSpace(os.Getenv("DATABASE_URL"))
	if dsn == "" {
		dsn = "uber:uber@tcp(127.0.0.1:3327)/uber_development?parseTime=true&multiStatements=true"
	}
	sec := strings.TrimSpace(os.Getenv("JWT_SECRET"))
	if sec == "" {
		sec = "dev-secret-do-not-use-in-prod"
	}
	addr := strings.TrimSpace(os.Getenv("HTTP_ADDR"))
	if addr == "" {
		addr = ":3110"
	}
	ai := strings.TrimSpace(os.Getenv("AI_WORKER_URL"))
	aiTok := strings.TrimSpace(os.Getenv("AI_INTERNAL_TOKEN"))
	if aiTok == "" {
		aiTok = "dev-internal-token"
	}
	// ADR 0001: 都市内ライドは resolution 9 (edge ~174m, area ~0.1 km²) を default
	res := 9
	if s := strings.TrimSpace(os.Getenv("H3_RESOLUTION")); s != "" {
		if v, err := strconv.Atoi(s); err == nil && v >= 0 && v <= 15 {
			res = v
		}
	}
	return &Config{
		Addr:            addr,
		DatabaseURL:     dsn,
		JWTSecret:       sec,
		AIWorkerURL:     ai,
		AIInternalToken: aiTok,
		H3Resolution:    res,
	}, nil
}

func (c *Config) MustValidate() error {
	if len(c.JWTSecret) < 8 {
		return fmt.Errorf("JWT_SECRET must be at least 8 characters")
	}
	if c.H3Resolution < 0 || c.H3Resolution > 15 {
		return fmt.Errorf("H3_RESOLUTION must be in [0, 15]")
	}
	return nil
}
