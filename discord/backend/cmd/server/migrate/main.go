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
		b, err := os.ReadFile(f)
		if err != nil {
			panic(err)
		}
		fmt.Printf("applying %s\n", filepath.Base(f))
		if _, err := db.Exec(string(b)); err != nil {
			panic(fmt.Errorf("%s: %w", f, err))
		}
	}
	fmt.Println("migrate: ok")
}
