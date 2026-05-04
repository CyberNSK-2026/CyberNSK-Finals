package main

import (
	"database/sql"
	"net/http"
	"strings"
)

type createBrandRequest struct {
	Name string `json:"name"`
}

type createProductRequest struct {
	BrandID          int64  `json:"brand_id"`
	Title            string `json:"title"`
	ShortDescription string `json:"short_description"`
	Price            int    `json:"price"`
}

type createDescriptionRequest struct {
	Description string `json:"description"`
	Top         string `json:"top"`
	Middle      string `json:"middle"`
	Base        string `json:"base"`
}

func (a *app) handleListBrands(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := contextWithTimeout(r.Context())
	defer cancel()

	rows, err := a.db.QueryContext(ctx, `SELECT id, name FROM brand WHERE is_marketplace_brand = TRUE ORDER BY name`)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load brands")
		return
	}
	defer rows.Close()

	var brands []brand
	for rows.Next() {
		var item brand
		if err := rows.Scan(&item.ID, &item.Name); err != nil {
			writeError(w, http.StatusInternalServerError, "failed to load brands")
			return
		}
		brands = append(brands, item)
	}

	writeJSON(w, http.StatusOK, map[string]any{"brands": brands})
}

func (a *app) handleSellerCreateProduct(w http.ResponseWriter, r *http.Request, user *buyer) {
	var req createProductRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	req.Title = strings.TrimSpace(req.Title)
	req.ShortDescription = strings.TrimSpace(req.ShortDescription)
	if req.BrandID <= 0 || req.Title == "" || req.ShortDescription == "" || req.Price < 0 {
		writeError(w, http.StatusBadRequest, "invalid product payload")
		return
	}

	ctx, cancel := contextWithTimeout(r.Context())
	defer cancel()

	const query = `
		INSERT INTO product (brand_id, title, short_description, price, created_by)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id
	`

	var productID int64
	if err := a.db.QueryRowContext(ctx, query, req.BrandID, req.Title, req.ShortDescription, req.Price, user.ID).Scan(&productID); err != nil {
		if isForeignKeyViolation(err) {
			writeError(w, http.StatusNotFound, "brand not found")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to create product")
		return
	}

	card, err := a.getProductCard(ctx, productID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load product")
		return
	}

	writeJSON(w, http.StatusCreated, map[string]any{"product": card})
}

func (a *app) handleSellerCreateDescription(w http.ResponseWriter, r *http.Request, user *buyer) {
	productID, err := parsePathInt(r, "product_id")
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid product id")
		return
	}

	var req createDescriptionRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	req.Description = strings.TrimSpace(req.Description)
	req.Top = strings.TrimSpace(req.Top)
	req.Middle = strings.TrimSpace(req.Middle)
	req.Base = strings.TrimSpace(req.Base)
	if req.Description == "" || req.Top == "" || req.Middle == "" || req.Base == "" {
		writeError(w, http.StatusBadRequest, "all note fields are required")
		return
	}

	ctx, cancel := contextWithTimeout(r.Context())
	defer cancel()

	owned, err := a.isSellerProductOwner(ctx, productID, user.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to create description")
		return
	}
	if !owned {
		writeError(w, http.StatusForbidden, "product belongs to another seller")
		return
	}

	const query = `
		INSERT INTO description (product_id, description, top, middle, base)
		VALUES ($1, $2, $3, $4, $5)
	`

	if _, err := a.db.ExecContext(ctx, query, productID, req.Description, req.Top, req.Middle, req.Base); err != nil {
		if err == sql.ErrNoRows || isForeignKeyViolation(err) {
			writeError(w, http.StatusNotFound, "product not found")
			return
		}
		if isUniqueViolation(err) {
			writeError(w, http.StatusConflict, "description already exists")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to create description")
		return
	}

	writeJSON(w, http.StatusCreated, map[string]any{
		"description": productNotes{
			ProductID:   productID,
			Description: req.Description,
			Top:         req.Top,
			Middle:      req.Middle,
			Base:        req.Base,
		},
	})
}
