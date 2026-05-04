package main

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"sort"

	"github.com/go-sql-driver/mysql"

	"github.com/hiratatomoaki/service-architecture-lab/discord/backend/internal/config"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		panic(err)
	}

	mc, err := mysql.ParseDSN(cfg.DatabaseURL)
	if err != nil {
		panic(err)
	}
	mc.MultiStatements = true
	dsn := mc.FormatDSN()

	db, err := sql.Open("mysql", dsn)
	if err != nil {
		panic(err)
	}
	defer db.Close()
	if err := db.Ping(); err != nil {
		panic(err)
	}

	if _, err := db.Exec(`CREATE TABLE IF NOT EXISTS schema_migrations (
		version VARCHAR(255) NOT NULL PRIMARY KEY,
		applied_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
	)`); err != nil {
		panic(err)
	}

	applied := map[string]bool{}
	rows, err := db.Query(`SELECT version FROM schema_migrations`)
	if err != nil {
		panic(err)
	}
	for rows.Next() {
		var v string
		if err := rows.Scan(&v); err != nil {
			rows.Close()
			panic(err)
		}
		applied[v] = true
	}
	rows.Close()

	migrationDir := filepath.Join("migrations")
	if len(os.Args) > 1 && os.Args[1] != "" {
		migrationDir = os.Args[1]
	}
	abs, err := filepath.Abs(migrationDir)
	if err != nil {
		panic(err)
	}
	files, err := filepath.Glob(filepath.Join(abs, "*.up.sql"))
	if err != nil {
		panic(err)
	}
	sort.Strings(files)
	if len(files) == 0 {
		fmt.Fprintf(os.Stderr, "no migrations in %s\n", abs)
		os.Exit(1)
	}

	for _, f := range files {
		version := filepath.Base(f)
		if applied[version] {
			fmt.Printf("skip %s (already applied)\n", version)
			continue
		}
		b, err := os.ReadFile(f)
		if err != nil {
			panic(err)
		}
		fmt.Printf("applying %s\n", version)
		if _, err := db.Exec(string(b)); err != nil {
			panic(fmt.Errorf("%s: %w", f, err))
		}
		if _, err := db.Exec(`INSERT INTO schema_migrations (version) VALUES (?)`, version); err != nil {
			panic(fmt.Errorf("record %s: %w", version, err))
		}
	}
	fmt.Println("migrate: ok")
}
