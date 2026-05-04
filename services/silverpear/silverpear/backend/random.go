package main

import "math/rand"

func newPredictableRNG(seed int64) *rand.Rand {
	return rand.New(rand.NewSource(seed))
}
