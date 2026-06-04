package auth

import (
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
)

// ingest (machine) 経路の API key (ADR 0004)。key は高エントロピー前提なので bcrypt ではなく
// sha256 hex で保存し、hash 一致を O(1) lookup する。比較は constant-time。
func HashAPIKey(plain string) string {
	sum := sha256.Sum256([]byte(plain))
	return hex.EncodeToString(sum[:])
}

// SameAPIKeyHash は 2 つの hex hash を constant-time 比較する。
func SameAPIKeyHash(a, b string) bool {
	return subtle.ConstantTimeCompare([]byte(a), []byte(b)) == 1
}
