package main

import (
	"os"
	"strconv"
	"time"
)

type config struct {
	Addr              string
	DatabaseURL       string
	MigrationsDir     string
	SessionCookieName string
	SaleDuration      time.Duration
}

func loadConfig() config {
	return config{
		Addr:              getenv("SILVERPEAR_ADDR", "0.0.0.0:8080"),
		DatabaseURL:       getenv("SILVERPEAR_DB_URL", "postgres://silverpear:silverpear@db:5432/silverpear?sslmode=disable"),
		MigrationsDir:     getenv("SILVERPEAR_MIGRATIONS_DIR", "/app/migrations"),
		SessionCookieName: getenv("SILVERPEAR_SESSION_COOKIE", "silverpear_session"),
		SaleDuration:      time.Duration(getenvInt("SILVERPEAR_SALE_HOURS", 72)) * time.Hour,
	}
}

func getenv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func getenvInt(key string, fallback int) int {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}

	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}

	return parsed
}
