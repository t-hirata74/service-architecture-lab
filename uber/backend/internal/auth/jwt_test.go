package auth

import (
	"strings"
	"testing"
	"time"
)

func TestSignAndParse_Roundtrip(t *testing.T) {
	secret := []byte("dev-secret-do-not-use-in-prod")

	for _, role := range []string{"rider", "driver"} {
		token, err := SignUserToken(secret, 42, role, time.Hour)
		if err != nil {
			t.Fatalf("Sign: %v", err)
		}
		cl, err := ParseUserToken(secret, token)
		if err != nil {
			t.Fatalf("Parse: %v", err)
		}
		if cl.UserID != 42 {
			t.Errorf("UserID = %d, want 42", cl.UserID)
		}
		if cl.Role != role {
			t.Errorf("Role = %q, want %q", cl.Role, role)
		}
	}
}

func TestParse_TamperedToken(t *testing.T) {
	secret := []byte("dev-secret-do-not-use-in-prod")
	token, err := SignUserToken(secret, 1, "rider", time.Hour)
	if err != nil {
		t.Fatalf("Sign: %v", err)
	}
	// 1 文字書き換えて改ざん
	tampered := token[:len(token)-2] + "Xx"
	if _, err := ParseUserToken(secret, tampered); err == nil {
		t.Error("expected error for tampered token")
	}
}

func TestParse_WrongSecret(t *testing.T) {
	token, err := SignUserToken([]byte("secret-A-very-long"), 1, "rider", time.Hour)
	if err != nil {
		t.Fatalf("Sign: %v", err)
	}
	if _, err := ParseUserToken([]byte("secret-B-different"), token); err == nil {
		t.Error("expected error for wrong secret")
	}
}

func TestParse_Expired(t *testing.T) {
	secret := []byte("dev-secret-do-not-use-in-prod")
	token, err := SignUserToken(secret, 1, "rider", -time.Minute)
	if err != nil {
		t.Fatalf("Sign: %v", err)
	}
	_, err = ParseUserToken(secret, token)
	if err == nil {
		t.Error("expected error for expired token")
	} else if !strings.Contains(err.Error(), "expired") {
		t.Errorf("expected expired error, got %v", err)
	}
}

func TestHashAndCheckPassword(t *testing.T) {
	hash, err := HashPassword("hunter2-very-secret")
	if err != nil {
		t.Fatalf("Hash: %v", err)
	}
	if !CheckPassword(hash, "hunter2-very-secret") {
		t.Error("CheckPassword should match")
	}
	if CheckPassword(hash, "wrong-password") {
		t.Error("CheckPassword should not match wrong password")
	}
}
