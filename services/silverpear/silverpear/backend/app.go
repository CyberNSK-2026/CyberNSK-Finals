package main

import (
	"context"
	"database/sql"
	"errors"
	"log"
	"net/http"
	"time"
)

type app struct {
	cfg          config
	db           *sql.DB
	sessions     *sessionStore
	serviceStart time.Time
	saleEndsAt   time.Time
}

func newApp(cfg config) (*app, error) {
	db, err := openDatabase(cfg.DatabaseURL)
	if err != nil {
		return nil, err
	}

	if err := applyMigrations(db, cfg.MigrationsDir); err != nil {
		return nil, err
	}

	start := time.Now().UTC()
	return &app{
		cfg:          cfg,
		db:           db,
		sessions:     newSessionStore(),
		serviceStart: start,
		saleEndsAt:   start.Add(cfg.SaleDuration),
	}, nil
}

func (a *app) routes() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /api/health", a.handleHealth)
	mux.HandleFunc("GET /api/storefront", a.handleStorefront)
	mux.HandleFunc("GET /api/products/{product_id}", a.handleGetProduct)
	mux.HandleFunc("GET /api/brands", a.handleListBrands)

	mux.HandleFunc("POST /api/register", a.handleRegister)
	mux.HandleFunc("POST /api/login", a.handleLogin)
	mux.HandleFunc("POST /api/logout", a.handleLogout)
	mux.Handle("GET /api/me", a.withAuth(a.handleMe))

	mux.Handle("POST /api/products", a.withSeller(a.handleSellerCreateProduct))
	mux.Handle("POST /api/products/{product_id}/description", a.withSeller(a.handleSellerCreateDescription))

	mux.Handle("POST /api/wheel/spin", a.withBuyer(a.handleWheelSpin))
	mux.Handle("POST /api/orders", a.withBuyer(a.handleCreateOrder))
	mux.Handle("POST /api/orders/{order_id}/items", a.withBuyer(a.handleAddOrderItem))
	mux.Handle("GET /api/orders", a.withBuyer(a.handleListOrders))
	mux.Handle("GET /api/orders/{order_id}", a.withBuyer(a.handleGetOrder))
	mux.Handle("POST /api/orders/{order_id}/checkout", a.withBuyer(a.handleCheckoutOrder))
	mux.Handle("POST /api/orders/{order_id}/apply-promocode", a.withBuyer(a.handleApplyPromocode))
	mux.Handle("GET /api/products/{product_id}/notes", a.withBuyer(a.handleGetProductNotes))
	mux.Handle("GET /api/list_transaction/{id}", a.withBuyer(a.handleGetListTransaction))
	mux.Handle("GET /api/transactions/{public_id}", a.withBuyer(a.handleGetLegacyTransaction))

	return a.withMiddleware(mux)
}

func (a *app) withMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		defer func() {
			if rec := recover(); rec != nil {
				log.Printf("panic during %s %s: %v", r.Method, r.URL.Path, rec)
				writeError(w, http.StatusInternalServerError, "internal server error")
			}

			log.Printf("%s %s %s", r.Method, r.URL.Path, time.Since(start).Round(time.Millisecond))
		}()

		next.ServeHTTP(w, r)
	})
}

type userHandler func(http.ResponseWriter, *http.Request, *buyer)

func (a *app) withAuth(next userHandler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		user, err := a.currentUser(r)
		if err != nil {
			if errors.Is(err, errUnauthorized) {
				writeError(w, http.StatusUnauthorized, "authentication required")
				return
			}

			log.Printf("failed to load current user: %v", err)
			writeError(w, http.StatusInternalServerError, "internal server error")
			return
		}

		next(w, r, user)
	})
}

func (a *app) withSeller(next userHandler) http.Handler {
	return a.withAuth(func(w http.ResponseWriter, r *http.Request, user *buyer) {
		if user.Role != "seller" {
			writeError(w, http.StatusForbidden, "seller access required")
			return
		}

		next(w, r, user)
	})
}

func (a *app) withBuyer(next userHandler) http.Handler {
	return a.withAuth(func(w http.ResponseWriter, r *http.Request, user *buyer) {
		if user.Role != "buyer" {
			writeError(w, http.StatusForbidden, "buyer access required")
			return
		}

		next(w, r, user)
	})
}

func (a *app) currentUser(r *http.Request) (*buyer, error) {
	cookie, err := r.Cookie(a.cfg.SessionCookieName)
	if err != nil {
		return nil, errUnauthorized
	}

	userID, ok := a.sessions.Get(cookie.Value)
	if !ok {
		return nil, errUnauthorized
	}

	user, err := a.getBuyerByID(r.Context(), userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			a.sessions.Delete(cookie.Value)
			return nil, errUnauthorized
		}
		return nil, err
	}

	return user, nil
}

func contextWithTimeout(parent context.Context) (context.Context, context.CancelFunc) {
	return context.WithTimeout(parent, 5*time.Second)
}
