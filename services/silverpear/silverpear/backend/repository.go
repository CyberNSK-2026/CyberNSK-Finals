package main

import (
	"context"
	"database/sql"
	"fmt"
	"time"
)

func (a *app) getBuyerByID(ctx context.Context, id int64) (*buyer, error) {
	const query = `
		SELECT id, name, password_hash, role, status, balance, total_spent, next_order_discount, wheel_used, created_at
		FROM buyer
		WHERE id = $1
	`

	var b buyer
	err := a.db.QueryRowContext(ctx, query, id).Scan(
		&b.ID,
		&b.Name,
		&b.PasswordHash,
		&b.Role,
		&b.Status,
		&b.Balance,
		&b.TotalSpent,
		&b.NextOrderDiscount,
		&b.WheelUsed,
		&b.CreatedAt,
	)
	if err != nil {
		return nil, err
	}

	return &b, nil
}

func (a *app) getBuyerByName(ctx context.Context, name string) (*buyer, error) {
	const query = `
		SELECT id, name, password_hash, role, status, balance, total_spent, next_order_discount, wheel_used, created_at
		FROM buyer
		WHERE name = $1
	`

	var b buyer
	err := a.db.QueryRowContext(ctx, query, name).Scan(
		&b.ID,
		&b.Name,
		&b.PasswordHash,
		&b.Role,
		&b.Status,
		&b.Balance,
		&b.TotalSpent,
		&b.NextOrderDiscount,
		&b.WheelUsed,
		&b.CreatedAt,
	)
	if err != nil {
		return nil, err
	}

	return &b, nil
}

func (a *app) getProductCard(ctx context.Context, productID int64) (*productCard, error) {
	const query = `
		SELECT p.id, p.brand_id, b.name, p.title, p.short_description, p.price
		FROM product p
		JOIN brand b ON b.id = p.brand_id
		WHERE p.id = $1 AND p.is_active = TRUE
	`

	var card productCard
	err := a.db.QueryRowContext(ctx, query, productID).Scan(
		&card.ID,
		&card.BrandID,
		&card.BrandName,
		&card.Title,
		&card.ShortDescription,
		&card.Price,
	)
	if err != nil {
		return nil, err
	}

	return &card, nil
}

func (a *app) getOrderRecordByPublicID(ctx context.Context, publicID string) (*orderRecord, error) {
	const query = `
		SELECT
			o.id,
			o.public_id::text,
			o.buyer_id,
			o.status,
			o.total_price,
			o.final_price,
			o.created_at,
			o.completed_at,
			o.promocode_id,
			p.code,
			p.discount_percent
		FROM purchase_order o
		LEFT JOIN promocode p ON p.id = o.promocode_id
		WHERE o.public_id = $1::uuid
	`

	var record orderRecord
	err := a.db.QueryRowContext(ctx, query, publicID).Scan(
		&record.ID,
		&record.PublicID,
		&record.BuyerID,
		&record.Status,
		&record.TotalPrice,
		&record.FinalPrice,
		&record.CreatedAt,
		&record.CompletedAt,
		&record.PromocodeID,
		&record.PromoCode,
		&record.PromoPct,
	)
	if err != nil {
		return nil, err
	}

	return &record, nil
}

func (a *app) getOwnedOrder(ctx context.Context, buyerID int64, publicID string) (*orderRecord, error) {
	order, err := a.getOrderRecordByPublicID(ctx, publicID)
	if err != nil {
		return nil, err
	}
	if order.BuyerID != buyerID {
		return nil, sql.ErrNoRows
	}
	return order, nil
}

func (a *app) loadOrderItems(ctx context.Context, orderID int64) ([]orderItem, error) {
	const query = `
		SELECT li.id, li.product_id, p.title, li.quantity, li.unit_price
		FROM list_transaction li
		JOIN product p ON p.id = li.product_id
		WHERE li.transaction_id = $1
		ORDER BY li.id
	`

	rows, err := a.db.QueryContext(ctx, query, orderID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var items []orderItem
	for rows.Next() {
		var item orderItem
		if err := rows.Scan(&item.ID, &item.ProductID, &item.Title, &item.Quantity, &item.UnitPrice); err != nil {
			return nil, err
		}
		items = append(items, item)
	}

	return items, rows.Err()
}

func (a *app) buildOrderResponse(ctx context.Context, record *orderRecord) (*orderResponse, error) {
	items, err := a.loadOrderItems(ctx, record.ID)
	if err != nil {
		return nil, err
	}

	response := &orderResponse{
		PublicID:   record.PublicID,
		BuyerID:    record.BuyerID,
		Status:     record.Status,
		TotalPrice: record.TotalPrice,
		FinalPrice: record.FinalPrice,
		Items:      items,
		CreatedAt:  record.CreatedAt,
	}
	if record.CompletedAt.Valid {
		value := record.CompletedAt.Time
		response.CompletedAt = &value
	}
	if record.PromoCode.Valid && record.PromoPct.Valid {
		response.Promocode = &promoDetails{
			Code:            record.PromoCode.String,
			DiscountPercent: int(record.PromoPct.Int64),
		}
	}

	return response, nil
}

func applyDiscount(total, discount int) int {
	if discount <= 0 {
		return total
	}
	if discount >= 100 {
		return 0
	}
	return total - (total*discount)/100
}

func (a *app) effectiveDiscount(user *buyer, promoDiscount int) int {
	discount := promoDiscount
	if user.NextOrderDiscount > discount {
		discount = user.NextOrderDiscount
	}
	if discount > 100 {
		return 100
	}
	return discount
}

func statusFromSpent(totalSpent int) string {
	switch {
	case totalSpent >= 100000:
		return "beauty legend"
	case totalSpent >= 50000:
		return "n0se"
	case totalSpent >= 15000:
		return "parfums maniac"
	case totalSpent >= 5000:
		return "niche"
	default:
		return "beginner"
	}
}

func (a *app) createHiddenJackpotCodeTx(ctx context.Context, tx *sql.Tx, userID int64, username string) (string, error) {
	code := a.jackpotCodeForUser(username)
	const query = `
		INSERT INTO promocode (code, discount_percent, owner_id, is_one_time, source)
		VALUES ($1, 100, $2, TRUE, 'wheel')
		ON CONFLICT (code) DO NOTHING
	`
	if _, err := tx.ExecContext(ctx, query, code, userID); err != nil {
		return "", err
	}
	return code, nil
}

func (a *app) jackpotCodeForUser(username string) string {
	const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	rng := newPredictableRNG(a.serviceStart.Unix())
	token := make([]byte, 10)
	for i := range token {
		token[i] = alphabet[rng.Intn(len(alphabet))]
	}
	return fmt.Sprintf("%s-%s", string(token), usernameHash(username))
}

func (a *app) spinOutcome(username string) (string, int, bool) {
	var hashSeed int64
	for _, ch := range username {
		hashSeed += int64(ch)
	}
	rng := newPredictableRNG(a.serviceStart.Unix() + hashSeed)
	if rng.Intn(100) == 0 {
		return "jackpot", 100, true
	}

	discounts := []int{5, 10, 15, 20}
	return "discount", discounts[rng.Intn(len(discounts))], false
}

func (a *app) hasUnlockedNotes(ctx context.Context, buyerID, productID int64) (bool, error) {
	const query = `
		SELECT EXISTS (
			SELECT 1
			FROM purchase_order o
			JOIN list_transaction li ON li.transaction_id = o.id
			WHERE o.buyer_id = $1
			  AND o.status = 'completed'
			  AND li.product_id = $2
		)
	`

	var unlocked bool
	if err := a.db.QueryRowContext(ctx, query, buyerID, productID).Scan(&unlocked); err != nil {
		return false, err
	}

	return unlocked, nil
}

func (a *app) loadProductNotes(ctx context.Context, productID int64) (*productNotes, error) {
	const query = `
		SELECT product_id, description, top, middle, base
		FROM description
		WHERE product_id = $1
	`

	var notes productNotes
	err := a.db.QueryRowContext(ctx, query, productID).Scan(
		&notes.ProductID,
		&notes.Description,
		&notes.Top,
		&notes.Middle,
		&notes.Base,
	)
	if err != nil {
		return nil, err
	}

	return &notes, nil
}

func (a *app) isSellerProductOwner(ctx context.Context, productID, sellerID int64) (bool, error) {
	const query = `
		SELECT EXISTS (
			SELECT 1
			FROM product
			WHERE id = $1
			  AND created_by = $2
		)
	`

	var owned bool
	if err := a.db.QueryRowContext(ctx, query, productID, sellerID).Scan(&owned); err != nil {
		return false, err
	}

	return owned, nil
}

func ensureDraftOrder(record *orderRecord) error {
	if record.Status != "draft" {
		return fmt.Errorf("order is not in draft status")
	}
	return nil
}

var (
	errInsufficientBalance = fmt.Errorf("insufficient balance")
	errEmptyOrder          = fmt.Errorf("empty order")
)

func (a *app) getOwnedOrderTx(ctx context.Context, tx *sql.Tx, buyerID int64, publicID string) (*orderRecord, error) {
	const query = `
		SELECT
			o.id,
			o.public_id::text,
			o.buyer_id,
			o.status,
			o.total_price,
			o.final_price,
			o.created_at,
			o.completed_at,
			o.promocode_id,
			p.code,
			p.discount_percent
		FROM purchase_order o
		LEFT JOIN promocode p ON p.id = o.promocode_id
		WHERE o.public_id = $1::uuid AND o.buyer_id = $2
		FOR UPDATE OF o
	`

	var record orderRecord
	err := tx.QueryRowContext(ctx, query, publicID, buyerID).Scan(
		&record.ID,
		&record.PublicID,
		&record.BuyerID,
		&record.Status,
		&record.TotalPrice,
		&record.FinalPrice,
		&record.CreatedAt,
		&record.CompletedAt,
		&record.PromocodeID,
		&record.PromoCode,
		&record.PromoPct,
	)
	if err != nil {
		return nil, err
	}

	return &record, nil
}

func (a *app) orderSubtotalTx(ctx context.Context, tx *sql.Tx, orderID int64) (int, error) {
	var total sql.NullInt64
	err := tx.QueryRowContext(ctx, `SELECT COALESCE(SUM(quantity * unit_price), 0) FROM list_transaction WHERE transaction_id = $1`, orderID).Scan(&total)
	if err != nil {
		return 0, err
	}
	return int(total.Int64), nil
}

func (a *app) getStoredPromoDiscountTx(ctx context.Context, tx *sql.Tx, orderID int64) (int, error) {
	var promoID sql.NullInt64
	if err := tx.QueryRowContext(ctx, `SELECT promocode_id FROM purchase_order WHERE id = $1`, orderID).Scan(&promoID); err != nil {
		return 0, err
	}
	if !promoID.Valid {
		return 0, nil
	}

	var discount int
	if err := tx.QueryRowContext(ctx, `SELECT discount_percent FROM promocode WHERE id = $1`, promoID.Int64).Scan(&discount); err != nil {
		return 0, err
	}

	return discount, nil
}

func (a *app) refreshOrderPricingTx(ctx context.Context, tx *sql.Tx, orderID int64, user *buyer) (int, int, error) {
	promoDiscount, err := a.getStoredPromoDiscountTx(ctx, tx, orderID)
	if err != nil {
		return 0, 0, err
	}
	return a.refreshOrderPricingWithPromoTx(ctx, tx, orderID, user, promoDiscount)
}

func (a *app) refreshOrderPricingWithPromoTx(ctx context.Context, tx *sql.Tx, orderID int64, user *buyer, promoDiscount int) (int, int, error) {
	total, err := a.orderSubtotalTx(ctx, tx, orderID)
	if err != nil {
		return 0, 0, err
	}

	final := applyDiscount(total, a.effectiveDiscount(user, promoDiscount))
	if _, err := tx.ExecContext(ctx, `UPDATE purchase_order SET total_price = $1, final_price = $2 WHERE id = $3`, total, final, orderID); err != nil {
		return 0, 0, err
	}

	return total, final, nil
}

type promoLookup struct {
	ID              sql.NullInt64
	Code            string
	DiscountPercent int
	IsOneTime       bool
}

func (a *app) lookupPromocodeVulnerable(ctx context.Context, tx *sql.Tx, code string, buyerID int64) (promoLookup, error) {
	query := fmt.Sprintf(`
		SELECT id, code, discount_percent, is_one_time
		FROM promocode
		WHERE code = '%s'
		  AND (owner_id IS NULL OR owner_id = %d)
		  AND used_by IS NULL
		LIMIT 1
	`, code, buyerID)

	var promo promoLookup
	if err := tx.QueryRowContext(ctx, query).Scan(&promo.ID, &promo.Code, &promo.DiscountPercent, &promo.IsOneTime); err != nil {
		return promo, err
	}

	return promo, nil
}

func (a *app) completeOrderWithTotalsTx(ctx context.Context, tx *sql.Tx, user *buyer, order *orderRecord, total, finalPrice int, promo promoLookup) (*buyer, error) {
	if total <= 0 {
		return nil, errEmptyOrder
	}
	if finalPrice > user.Balance {
		return nil, errInsufficientBalance
	}

	now := time.Now().UTC()
	if _, err := tx.ExecContext(ctx, `
		UPDATE purchase_order
		SET status = 'completed', total_price = $1, final_price = $2, completed_at = $3
		WHERE id = $4
	`, total, finalPrice, now, order.ID); err != nil {
		return nil, err
	}

	if promo.ID.Valid && promo.IsOneTime {
		if _, err := tx.ExecContext(ctx, `
			UPDATE promocode
			SET used_by = $1, used_at = $2
			WHERE id = $3 AND used_by IS NULL
		`, user.ID, now, promo.ID.Int64); err != nil {
			return nil, err
		}
	}

	newBalance := user.Balance - finalPrice
	newTotalSpent := user.TotalSpent + finalPrice
	newStatus := user.Status
	newNextDiscount := 0

	newStatus = statusFromSpent(newTotalSpent)
	if user.Status != "beauty legend" && newStatus == "beauty legend" {
		newNextDiscount = 100
	}

	if _, err := tx.ExecContext(ctx, `
		UPDATE buyer
		SET balance = $1, total_spent = $2, status = $3, next_order_discount = $4
		WHERE id = $5
	`, newBalance, newTotalSpent, newStatus, newNextDiscount, user.ID); err != nil {
		return nil, err
	}

	updated := *user
	updated.Balance = newBalance
	updated.TotalSpent = newTotalSpent
	updated.Status = newStatus
	updated.NextOrderDiscount = newNextDiscount
	return &updated, nil
}
