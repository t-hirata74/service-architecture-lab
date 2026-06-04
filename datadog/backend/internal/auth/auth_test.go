package auth

import (
	"testing"
	"time"
)

func TestJWTRoundTrip(t *testing.T) {
	secret := []byte("test-secret-123")
	tok, err := SignUserToken(secret, 42, time.Hour)
	if err != nil {
		t.Fatalf("sign: %v", err)
	}
	claims, err := ParseUserToken(secret, tok)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if claims.UserID != 42 {
		t.Fatalf("uid = %d, want 42", claims.UserID)
	}
}

func TestJWTWrongSecretRejected(t *testing.T) {
	tok, _ := SignUserToken([]byte("secret-a-xxxx"), 1, time.Hour)
	if _, err := ParseUserToken([]byte("secret-b-xxxx"), tok); err == nil {
		t.Fatal("expected error for wrong secret")
	}
}

func TestJWTExpiredRejected(t *testing.T) {
	secret := []byte("test-secret-123")
	tok, _ := SignUserToken(secret, 1, -time.Minute) // 既に期限切れ
	if _, err := ParseUserToken(secret, tok); err == nil {
		t.Fatal("expected error for expired token")
	}
}

func TestPassword(t *testing.T) {
	hash, err := HashPassword("supersecret123")
	if err != nil {
		t.Fatalf("hash: %v", err)
	}
	if !CheckPassword(hash, "supersecret123") {
		t.Fatal("correct password rejected")
	}
	if CheckPassword(hash, "wrong") {
		t.Fatal("wrong password accepted")
	}
}

func TestAPIKeyHash(t *testing.T) {
	h1 := HashAPIKey("dev-ingest-key")
	h2 := HashAPIKey("dev-ingest-key")
	if h1 != h2 {
		t.Fatal("hash not deterministic")
	}
	if len(h1) != 64 {
		t.Fatalf("hash len = %d, want 64 (sha256 hex)", len(h1))
	}
	if !SameAPIKeyHash(h1, h2) {
		t.Fatal("equal hashes compared unequal")
	}
	if SameAPIKeyHash(h1, HashAPIKey("other-key")) {
		t.Fatal("different hashes compared equal")
	}
}
