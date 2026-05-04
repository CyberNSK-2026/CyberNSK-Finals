package main

import (
	"database/sql"
	"time"
)

type buyer struct {
	ID                int64     `json:"id"`
	Name              string    `json:"name"`
	Role              string    `json:"role"`
	Status            string    `json:"status"`
	Balance           int       `json:"balance"`
	TotalSpent        int       `json:"total_spent"`
	NextOrderDiscount int       `json:"next_order_discount"`
	WheelUsed         bool      `json:"wheel_used"`
	CreatedAt         time.Time `json:"created_at"`
	PasswordHash      string    `json:"-"`
}

type brand struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
}

type productCard struct {
	ID               int64  `json:"id"`
	BrandID          int64  `json:"brand_id"`
	BrandName        string `json:"brand_name"`
	Title            string `json:"title"`
	ShortDescription string `json:"short_description"`
	Price            int    `json:"price"`
}

type productNotes struct {
	ProductID   int64  `json:"product_id"`
	Description string `json:"description"`
	Top         string `json:"top"`
	Middle      string `json:"middle"`
	Base        string `json:"base"`
}

type orderItem struct {
	ID        int64  `json:"id"`
	ProductID int64  `json:"product_id"`
	Title     string `json:"title"`
	Quantity  int    `json:"quantity"`
	UnitPrice int    `json:"unit_price"`
}

type promoDetails struct {
	Code            string `json:"code"`
	DiscountPercent int    `json:"discount_percent"`
}

type orderRecord struct {
	ID          int64
	PublicID    string
	BuyerID     int64
	Status      string
	TotalPrice  int
	FinalPrice  int
	CreatedAt   time.Time
	CompletedAt sql.NullTime
	PromocodeID sql.NullInt64
	PromoCode   sql.NullString
	PromoPct    sql.NullInt64
}

type orderResponse struct {
	PublicID    string        `json:"public_id"`
	BuyerID     int64         `json:"buyer_id"`
	Status      string        `json:"status"`
	TotalPrice  int           `json:"total_price"`
	FinalPrice  int           `json:"final_price"`
	Promocode   *promoDetails `json:"promocode"`
	Items       []orderItem   `json:"items"`
	CreatedAt   time.Time     `json:"created_at"`
	CompletedAt *time.Time    `json:"completed_at"`
}

type transactionItem struct {
	ID        int64        `json:"id"`
	ProductID int64        `json:"product_id"`
	Title     string       `json:"title"`
	Quantity  int          `json:"quantity"`
	UnitPrice int          `json:"unit_price"`
	Notes     productNotes `json:"notes"`
}
