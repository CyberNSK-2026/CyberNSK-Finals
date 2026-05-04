package main

import (
	"database/sql"
	"net/http"
	"time"
)

func (a *app) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"service": "silverpear-backend",
		"status":  "ok",
		"time":    time.Now().UTC().Format(time.RFC3339),
	})
}

func (a *app) handleStorefront(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := contextWithTimeout(r.Context())
	defer cancel()

	const query = `
		SELECT b.id, b.name, p.id, p.title, p.short_description, p.price
		FROM brand b
		LEFT JOIN product p ON p.brand_id = b.id AND p.is_active = TRUE
		WHERE b.is_marketplace_brand = TRUE
		ORDER BY b.name, p.id
	`

	rows, err := a.db.QueryContext(ctx, query)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load storefront")
		return
	}
	defer rows.Close()

	type brandGroup struct {
		ID       int64         `json:"id"`
		Name     string        `json:"name"`
		Products []productCard `json:"products"`
	}

	grouped := make(map[int64]*brandGroup)
	order := make([]int64, 0)

	for rows.Next() {
		var brandID int64
		var brandName string
		var productID sql.NullInt64
		var title sql.NullString
		var shortDescription sql.NullString
		var price sql.NullInt64

		if err := rows.Scan(&brandID, &brandName, &productID, &title, &shortDescription, &price); err != nil {
			writeError(w, http.StatusInternalServerError, "failed to load storefront")
			return
		}

		group, ok := grouped[brandID]
		if !ok {
			group = &brandGroup{ID: brandID, Name: brandName, Products: []productCard{}}
			grouped[brandID] = group
			order = append(order, brandID)
		}

		if productID.Valid {
			group.Products = append(group.Products, productCard{
				ID:               productID.Int64,
				BrandID:          brandID,
				BrandName:        brandName,
				Title:            title.String,
				ShortDescription: shortDescription.String,
				Price:            int(price.Int64),
			})
		}
	}

	brands := make([]brandGroup, 0, len(order))
	for _, brandID := range order {
		brands = append(brands, *grouped[brandID])
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"sale_ends_at": a.saleEndsAt.UTC().Format(time.RFC3339),
		"brands":       brands,
	})
}

func (a *app) handleGetProduct(w http.ResponseWriter, r *http.Request) {
	productID, err := parsePathInt(r, "product_id")
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid product id")
		return
	}

	ctx, cancel := contextWithTimeout(r.Context())
	defer cancel()

	card, err := a.getProductCard(ctx, productID)
	if err != nil {
		if err == sql.ErrNoRows {
			writeError(w, http.StatusNotFound, "product not found")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to load product")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{"product": card})
}
