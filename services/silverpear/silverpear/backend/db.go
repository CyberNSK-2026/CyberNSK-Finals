package main

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	_ "github.com/lib/pq"
)

func openDatabase(databaseURL string) (*sql.DB, error) {
	db, err := sql.Open("postgres", databaseURL)
	if err != nil {
		return nil, err
	}

	deadline := time.Now().Add(30 * time.Second)
	for {
		ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		err = db.PingContext(ctx)
		cancel()
		if err == nil {
			return db, nil
		}

		if time.Now().After(deadline) {
			return nil, fmt.Errorf("ping database: %w", err)
		}

		time.Sleep(time.Second)
	}
}

func applyMigrations(db *sql.DB, dir string) error {
	if err := ensureMigrationTable(db); err != nil {
		return err
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		return fmt.Errorf("read migrations dir %s: %w", dir, err)
	}

	var versions []string
	for _, entry := range entries {
		if entry.IsDir() || filepath.Ext(entry.Name()) != ".sql" {
			continue
		}
		versions = append(versions, entry.Name())
	}

	sort.Strings(versions)

	for _, version := range versions {
		applied, err := migrationApplied(db, version)
		if err != nil {
			return err
		}
		if applied {
			continue
		}

		path := filepath.Join(dir, version)
		if err := applyMigration(db, version, path); err != nil {
			return err
		}
	}

	return nil
}

func ensureMigrationTable(db *sql.DB) error {
	const query = `
CREATE TABLE IF NOT EXISTS schema_migrations (
    version TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
)`

	if _, err := db.Exec(query); err != nil {
		return fmt.Errorf("ensure migration table: %w", err)
	}

	return nil
}

func migrationApplied(db *sql.DB, version string) (bool, error) {
	var exists bool
	if err := db.QueryRow(`SELECT EXISTS(SELECT 1 FROM schema_migrations WHERE version = $1)`, version).Scan(&exists); err != nil {
		return false, fmt.Errorf("check migration %s: %w", version, err)
	}

	return exists, nil
}

func applyMigration(db *sql.DB, version, path string) error {
	body, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read migration %s: %w", version, err)
	}

	if strings.TrimSpace(string(body)) == "" {
		return fmt.Errorf("migration %s is empty", version)
	}

	tx, err := db.Begin()
	if err != nil {
		return fmt.Errorf("begin migration %s: %w", version, err)
	}

	if _, err := tx.Exec(string(body)); err != nil {
		tx.Rollback()
		return fmt.Errorf("apply migration %s: %w", version, err)
	}

	if _, err := tx.Exec(`INSERT INTO schema_migrations (version) VALUES ($1)`, version); err != nil {
		tx.Rollback()
		return fmt.Errorf("record migration %s: %w", version, err)
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit migration %s: %w", version, err)
	}

	return nil
}
