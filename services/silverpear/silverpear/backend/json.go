package main

import (
	"crypto/sha1"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/lib/pq"
)

var errUnauthorized = errors.New("unauthorized")

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

func readJSON(r *http.Request, dst any) error {
	defer r.Body.Close()
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	return decoder.Decode(dst)
}

func parsePathInt(r *http.Request, key string) (int64, error) {
	return strconv.ParseInt(r.PathValue(key), 10, 64)
}

func hashPassword(password string) string {
	sum := sha256.Sum256([]byte(password))
	return hex.EncodeToString(sum[:])
}

func checkPassword(hash, password string) bool {
	comparison := hashPassword(password)
	return subtle.ConstantTimeCompare([]byte(hash), []byte(comparison)) == 1
}

func usernameHash(value string) string {
	sum := sha1.Sum([]byte(strings.ToLower(value)))
	return hex.EncodeToString(sum[:4])
}

func postgresErrorCode(err error) string {
	var pqErr *pq.Error
	if errors.As(err, &pqErr) {
		return string(pqErr.Code)
	}
	return ""
}

func isUniqueViolation(err error) bool {
	return postgresErrorCode(err) == "23505"
}

func isForeignKeyViolation(err error) bool {
	return postgresErrorCode(err) == "23503"
}

func isInvalidTextRepresentation(err error) bool {
	return postgresErrorCode(err) == "22P02"
}
