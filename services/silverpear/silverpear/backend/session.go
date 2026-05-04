package main

import (
	"crypto/rand"
	"encoding/hex"
	"sync"
)

type sessionStore struct {
	mu       sync.RWMutex
	sessions map[string]int64
}

func newSessionStore() *sessionStore {
	return &sessionStore{sessions: make(map[string]int64)}
}

func (s *sessionStore) Create(userID int64) (string, error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}

	token := hex.EncodeToString(buf)
	s.mu.Lock()
	defer s.mu.Unlock()
	s.sessions[token] = userID
	return token, nil
}

func (s *sessionStore) Get(token string) (int64, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	userID, ok := s.sessions[token]
	return userID, ok
}

func (s *sessionStore) Delete(token string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.sessions, token)
}
