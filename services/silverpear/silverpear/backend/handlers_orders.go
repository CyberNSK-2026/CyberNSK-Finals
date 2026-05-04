package main

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"
)

type addOrderItemRequest struct {
	ProductID int64 `json:"product_id"`
	Quantity  int   `json:"quantity"`
}

type applyPromocodeRequest struct {
	Code string `json:"code"`
}

func (a *app) handleWheelSpin(w http.ResponseWriter, r *http.Request, user *buyer) {
	if user.WheelUsed {
		writeError(w, http.StatusConflict, "wheel already used")
		return
	}

	ctx, cancel := contextWithTimeout(r.Context())
	defer cancel()

	outcome, discount, jackpot := a.spinOutcome(user.Name)
	tx, err := a.db.BeginTx(ctx, nil)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to spin wheel")
		return
	}
	defer tx.Rollback()

	var code string
	if jackpot {
		code = a.jackpotCodeForUser(user.Name)
	} else {
		code = fmt.Sprintf("%s-%02d-WHEEL-%s", strings.ToUpper(user.Name), discount, usernameHash(user.Name))
		const insertPromo = `
			INSERT INTO promocode (code, discount_percent, owner_id, is_one_time, source)
			VALUES ($1, $2, $3, TRUE, 'wheel')
			ON CONFLICT (code) DO NOTHING
		`
		if _, err := tx.ExecContext(ctx, insertPromo, code, discount, user.ID); err != nil {
			writeError(w, http.StatusInternalServerError, "failed to spin wheel")
			return
		}
	}

	if _, err := tx.ExecContext(ctx, `UPDATE buyer SET wheel_used = TRUE WHERE id = $1`, user.ID); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to spin wheel")
		return
	}

	if err := tx.Commit(); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to spin wheel")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"outcome":          outcome,
		"discount_percent": discount,
		"code":             code,
		"is_jackpot":       jackpot,
	})
}

func (a *app) handleCreateOrder(w http.ResponseWriter, r *http.Request, user *buyer) {
	ctx, cancel := contextWithTimeout(r.Context())
	defer cancel()

	const query = `
		INSERT INTO purchase_order (buyer_id, status, total_price, final_price)
		VALUES ($1, 'draft', 0, 0)
		RETURNING public_id::text, created_at
	`

	var publicID string
	var createdAt time.Time
	if err := a.db.QueryRowContext(ctx, query, user.ID).Scan(&publicID, &createdAt); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to create order")
		return
	}

	writeJSON(w, http.StatusCreated, map[string]any{
		"order": orderResponse{
			PublicID:   publicID,
			BuyerID:    user.ID,
			Status:     "draft",
			TotalPrice: 0,
			FinalPrice: 0,
			Promocode:  nil,
			Items:      []orderItem{},
			CreatedAt:  createdAt,
		},
	})
}

func (a *app) handleAddOrderItem(w http.ResponseWriter, r *http.Request, user *buyer) {
	orderID := r.PathValue("order_id")

	var req addOrderItemRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.ProductID <= 0 || req.Quantity <= 0 {
		writeError(w, http.StatusBadRequest, "invalid order item payload")
		return
	}

	ctx, cancel := contextWithTimeout(r.Context())
	defer cancel()

	tx, err := a.db.BeginTx(ctx, nil)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to update order")
		return
	}
	defer tx.Rollback()

	order, err := a.getOwnedOrderTx(ctx, tx, user.ID, orderID)
	if err != nil {
		a.writeOrderLoadError(w, err)
		return
	}
	if err := ensureDraftOrder(order); err != nil {
		writeError(w, http.StatusConflict, err.Error())
		return
	}

	product, err := a.getProductCard(ctx, req.ProductID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, "product not found")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to update order")
		return
	}

	const insertItem = `
		INSERT INTO list_transaction (transaction_id, product_id, quantity, unit_price)
		VALUES ($1, $2, $3, $4)
	`
	if _, err := tx.ExecContext(ctx, insertItem, order.ID, req.ProductID, req.Quantity, product.Price); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to update order")
		return
	}

	if _, _, err := a.refreshOrderPricingTx(ctx, tx, order.ID, user); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to update order")
		return
	}

	if err := tx.Commit(); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to update order")
		return
	}

	record, err := a.getOwnedOrder(ctx, user.ID, orderID)
	if err != nil {
		a.writeOrderLoadError(w, err)
		return
	}

	response, err := a.buildOrderResponse(ctx, record)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to update order")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{"order": response})
}

func (a *app) handleListOrders(w http.ResponseWriter, r *http.Request, user *buyer) {
	ctx, cancel := contextWithTimeout(r.Context())
	defer cancel()

	const query = `
		SELECT public_id::text, status, total_price, final_price, created_at, completed_at
		FROM purchase_order
		WHERE buyer_id = $1
		ORDER BY created_at DESC
	`

	rows, err := a.db.QueryContext(ctx, query, user.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load orders")
		return
	}
	defer rows.Close()

	type summary struct {
		PublicID    string     `json:"public_id"`
		Status      string     `json:"status"`
		TotalPrice  int        `json:"total_price"`
		FinalPrice  int        `json:"final_price"`
		CreatedAt   time.Time  `json:"created_at"`
		CompletedAt *time.Time `json:"completed_at"`
	}

	var orders []summary
	for rows.Next() {
		var item summary
		var completedAt sql.NullTime
		if err := rows.Scan(&item.PublicID, &item.Status, &item.TotalPrice, &item.FinalPrice, &item.CreatedAt, &completedAt); err != nil {
			writeError(w, http.StatusInternalServerError, "failed to load orders")
			return
		}
		if completedAt.Valid {
			value := completedAt.Time
			item.CompletedAt = &value
		}
		orders = append(orders, item)
	}

	writeJSON(w, http.StatusOK, map[string]any{"orders": orders})
}

func (a *app) handleGetOrder(w http.ResponseWriter, r *http.Request, user *buyer) {
	orderID := r.PathValue("order_id")
	ctx, cancel := contextWithTimeout(r.Context())
	defer cancel()

	record, err := a.getOwnedOrder(ctx, user.ID, orderID)
	if err != nil {
		a.writeOrderLoadError(w, err)
		return
	}

	response, err := a.buildOrderResponse(ctx, record)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load order")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{"order": response})
}

func (a *app) handleCheckoutOrder(w http.ResponseWriter, r *http.Request, user *buyer) {
	orderPublicID := r.PathValue("order_id")
	ctx, cancel := contextWithTimeout(r.Context())
	defer cancel()

	tx, err := a.db.BeginTx(ctx, nil)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to checkout order")
		return
	}
	defer tx.Rollback()

	order, err := a.getOwnedOrderTx(ctx, tx, user.ID, orderPublicID)
	if err != nil {
		a.writeOrderLoadError(w, err)
		return
	}
	if err := ensureDraftOrder(order); err != nil {
		writeError(w, http.StatusConflict, err.Error())
		return
	}

	total, final, err := a.refreshOrderPricingTx(ctx, tx, order.ID, user)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to checkout order")
		return
	}

	promo := promoLookup{
		ID:              order.PromocodeID,
		Code:            order.PromoCode.String,
		DiscountPercent: int(order.PromoPct.Int64),
		IsOneTime:       true,
	}
	if _, err := a.completeOrderWithTotalsTx(ctx, tx, user, order, total, final, promo); err != nil {
		if errors.Is(err, errInsufficientBalance) {
			writeError(w, http.StatusConflict, "insufficient balance")
			return
		}
		if errors.Is(err, errEmptyOrder) {
			writeError(w, http.StatusConflict, "order has no items")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to checkout order")
		return
	}

	if err := tx.Commit(); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to checkout order")
		return
	}

	record, err := a.getOwnedOrder(ctx, user.ID, orderPublicID)
	if err != nil {
		a.writeOrderLoadError(w, err)
		return
	}

	response, err := a.buildOrderResponse(ctx, record)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to checkout order")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{"order": response})
}

func (a *app) handleApplyPromocode(w http.ResponseWriter, r *http.Request, user *buyer) {
	orderPublicID := r.PathValue("order_id")

	var req applyPromocodeRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	req.Code = strings.TrimSpace(req.Code)
	if req.Code == "" {
		writeError(w, http.StatusBadRequest, "promocode is required")
		return
	}

	ctx, cancel := contextWithTimeout(r.Context())
	defer cancel()

	tx, err := a.db.BeginTx(ctx, nil)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to apply promocode")
		return
	}
	defer tx.Rollback()

	order, err := a.getOwnedOrderTx(ctx, tx, user.ID, orderPublicID)
	if err != nil {
		a.writeOrderLoadError(w, err)
		return
	}
	if err := ensureDraftOrder(order); err != nil {
		writeError(w, http.StatusConflict, err.Error())
		return
	}

	promo, err := a.lookupPromocodeVulnerable(ctx, tx, req.Code, user.ID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, "promocode not found")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to apply promocode")
		return
	}

	if promo.ID.Valid {
		if _, err := tx.ExecContext(ctx, `UPDATE purchase_order SET promocode_id = $1 WHERE id = $2`, promo.ID.Int64, order.ID); err != nil {
			writeError(w, http.StatusInternalServerError, "failed to apply promocode")
			return
		}
	}

	total, final, err := a.refreshOrderPricingWithPromoTx(ctx, tx, order.ID, user, promo.DiscountPercent)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to apply promocode")
		return
	}

	if promo.DiscountPercent >= 100 || final == 0 {
		if _, err := a.completeOrderWithTotalsTx(ctx, tx, user, order, total, final, promo); err != nil {
			if errors.Is(err, errEmptyOrder) {
				writeError(w, http.StatusConflict, "order has no items")
				return
			}
			writeError(w, http.StatusInternalServerError, "failed to apply promocode")
			return
		}
	}

	if err := tx.Commit(); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to apply promocode")
		return
	}

	record, err := a.getOwnedOrder(ctx, user.ID, orderPublicID)
	if err != nil {
		a.writeOrderLoadError(w, err)
		return
	}

	response, err := a.buildOrderResponse(ctx, record)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to apply promocode")
		return
	}

	if promo.DiscountPercent > 0 {
		response.Promocode = &promoDetails{
			Code:            promo.Code,
			DiscountPercent: promo.DiscountPercent,
		}
	}

	writeJSON(w, http.StatusOK, map[string]any{"order": response})
}

func (a *app) handleGetProductNotes(w http.ResponseWriter, r *http.Request, user *buyer) {
	productID, err := parsePathInt(r, "product_id")
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid product id")
		return
	}

	ctx, cancel := contextWithTimeout(r.Context())
	defer cancel()

	unlocked, err := a.hasUnlockedNotes(ctx, user.ID, productID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load notes")
		return
	}
	if !unlocked {
		writeError(w, http.StatusForbidden, "product notes are locked")
		return
	}

	notes, err := a.loadProductNotes(ctx, productID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, "product notes not found")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to load notes")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{"notes": notes})
}

func (a *app) handleGetListTransaction(w http.ResponseWriter, r *http.Request, user *buyer) {
	listID, err := parsePathInt(r, "id")
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid list transaction id")
		return
	}

	ctx, cancel := contextWithTimeout(r.Context())
	defer cancel()

	const query = `
		SELECT li.id, o.public_id::text, li.product_id, li.quantity, li.unit_price
		FROM list_transaction li
		JOIN purchase_order o ON o.id = li.transaction_id
		WHERE li.id = $1
	`

	var response struct {
		Item struct {
			ID                  int64  `json:"id"`
			TransactionPublicID string `json:"transaction_public_id"`
			ProductID           int64  `json:"product_id"`
			Quantity            int    `json:"quantity"`
			UnitPrice           int    `json:"unit_price"`
		} `json:"item"`
	}

	if err := a.db.QueryRowContext(ctx, query, listID).Scan(
		&response.Item.ID,
		&response.Item.TransactionPublicID,
		&response.Item.ProductID,
		&response.Item.Quantity,
		&response.Item.UnitPrice,
	); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, "list transaction not found")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to load list transaction")
		return
	}

	writeJSON(w, http.StatusOK, response)
}

func (a *app) handleGetLegacyTransaction(w http.ResponseWriter, r *http.Request, user *buyer) {
	publicID := r.PathValue("public_id")
	ctx, cancel := contextWithTimeout(r.Context())
	defer cancel()

	order, err := a.getOrderRecordByPublicID(ctx, publicID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) || isInvalidTextRepresentation(err) {
			writeError(w, http.StatusNotFound, "transaction not found")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to load transaction")
		return
	}

	const query = `
		SELECT
			li.id,
			li.product_id,
			p.title,
			li.quantity,
			li.unit_price,
			d.product_id,
			d.description,
			d.top,
			d.middle,
			d.base
		FROM list_transaction li
		JOIN product p ON p.id = li.product_id
		JOIN description d ON d.product_id = p.id
		WHERE li.transaction_id = $1
		ORDER BY li.id
	`

	rows, err := a.db.QueryContext(ctx, query, order.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to load transaction")
		return
	}
	defer rows.Close()

	var items []transactionItem
	for rows.Next() {
		var item transactionItem
		if err := rows.Scan(
			&item.ID,
			&item.ProductID,
			&item.Title,
			&item.Quantity,
			&item.UnitPrice,
			&item.Notes.ProductID,
			&item.Notes.Description,
			&item.Notes.Top,
			&item.Notes.Middle,
			&item.Notes.Base,
		); err != nil {
			writeError(w, http.StatusInternalServerError, "failed to load transaction")
			return
		}
		items = append(items, item)
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"transaction": map[string]any{
			"public_id": order.PublicID,
			"buyer_id":  order.BuyerID,
			"status":    order.Status,
			"items":     items,
		},
	})
}

func (a *app) writeOrderLoadError(w http.ResponseWriter, err error) {
	if errors.Is(err, sql.ErrNoRows) || isInvalidTextRepresentation(err) {
		writeError(w, http.StatusNotFound, "order not found")
		return
	}
	writeError(w, http.StatusInternalServerError, "failed to load order")
}

func beginTx(ctx context.Context, db *sql.DB) (*sql.Tx, error) {
	return db.BeginTx(ctx, nil)
}
