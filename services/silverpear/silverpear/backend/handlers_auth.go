package main

import (
	"database/sql"
	"errors"
	"net/http"
	"strings"
	"time"
)

type registerRequest struct {
	Name     string `json:"name"`
	Password string `json:"password"`
	Role     string `json:"role"`
	Status   string `json:"status"`
}

type loginRequest struct {
	Name     string `json:"name"`
	Password string `json:"password"`
}

func (a *app) handleRegister(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" || req.Password == "" {
		writeError(w, http.StatusBadRequest, "name and password are required")
		return
	}

	role := strings.TrimSpace(req.Role)
	if role == "" {
		writeError(w, http.StatusBadRequest, "role is required")
		return
	}
	if role != "buyer" && role != "seller" {
		writeError(w, http.StatusBadRequest, "invalid role")
		return
	}

	status := strings.TrimSpace(req.Status)
	if status == "" {
		status = "beginner"
	}

	allowedStatuses := map[string]bool{
		"beginner":       true,
		"niche":          true,
		"parfums maniac": true,
		"n0se":           true,
	}
	if !allowedStatuses[status] && status != "beauty legend" {
		writeError(w, http.StatusBadRequest, "invalid status")
		return
	}

	nextDiscount := 0
	if status == "beauty legend" {
		nextDiscount = 100
	}

	ctx, cancel := contextWithTimeout(r.Context())
	defer cancel()

	tx, err := a.db.BeginTx(ctx, nil)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to register user")
		return
	}
	defer tx.Rollback()

	const query = `
		INSERT INTO buyer (name, password_hash, role, status, balance, total_spent, next_order_discount, wheel_used)
		VALUES ($1, $2, $3, $4, 2000, 0, $5, FALSE)
		RETURNING id, created_at
	`

	var userID int64
	var createdAt time.Time
	if err := tx.QueryRowContext(ctx, query, req.Name, hashPassword(req.Password), role, status, nextDiscount).Scan(&userID, &createdAt); err != nil {
		if isUniqueViolation(err) {
			writeError(w, http.StatusConflict, "user already exists")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to register user")
		return
	}

	if _, err := a.createHiddenJackpotCodeTx(ctx, tx, userID, req.Name); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to register user")
		return
	}

	if err := tx.Commit(); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to register user")
		return
	}

	writeJSON(w, http.StatusCreated, map[string]any{
		"buyer": buyer{
			ID:                userID,
			Name:              req.Name,
			Role:              role,
			Status:            status,
			Balance:           2000,
			TotalSpent:        0,
			NextOrderDiscount: nextDiscount,
			WheelUsed:         false,
			CreatedAt:         createdAt,
		},
	})
}

func (a *app) handleLogin(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	ctx, cancel := contextWithTimeout(r.Context())
	defer cancel()

	user, err := a.getBuyerByName(ctx, strings.TrimSpace(req.Name))
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusUnauthorized, "invalid credentials")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to authenticate")
		return
	}

	if !checkPassword(user.PasswordHash, req.Password) {
		writeError(w, http.StatusUnauthorized, "invalid credentials")
		return
	}

	token, err := a.sessions.Create(user.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to create session")
		return
	}

	http.SetCookie(w, &http.Cookie{
		Name:     a.cfg.SessionCookieName,
		Value:    token,
		Path:     "/",
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
		MaxAge:   7 * 24 * 3600,
	})

	writeJSON(w, http.StatusOK, map[string]any{"buyer": sanitizeBuyer(user)})
}

func (a *app) handleLogout(w http.ResponseWriter, r *http.Request) {
	if cookie, err := r.Cookie(a.cfg.SessionCookieName); err == nil {
		a.sessions.Delete(cookie.Value)
	}

	http.SetCookie(w, &http.Cookie{
		Name:     a.cfg.SessionCookieName,
		Value:    "",
		Path:     "/",
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
		MaxAge:   -1,
	})

	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (a *app) handleMe(w http.ResponseWriter, r *http.Request, user *buyer) {
	writeJSON(w, http.StatusOK, map[string]any{"buyer": sanitizeBuyer(user)})
}

func sanitizeBuyer(user *buyer) buyer {
	copy := *user
	copy.PasswordHash = ""
	return copy
}
