// Package auth は HS256 JWT bearer + bcrypt password の最小機構。
// discord/backend/internal/auth と同形だが、Claims に role フィールドを追加して
// rider/driver の区別を token に乗せている (uber 固有)。
package auth

import (
	"fmt"
	"strconv"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Claims は uber の JWT claim。discord と異なるのは role を追加で運ぶ点のみ。
// role があれば middleware で role-based 認可 (driver only endpoint 等) を 1 段で済ませられる。
type Claims struct {
	UserID int64  `json:"uid"`
	Role   string `json:"role"` // "rider" | "driver"
	jwt.RegisteredClaims
}

func SignUserToken(secret []byte, userID int64, role string, ttl time.Duration) (string, error) {
	now := time.Now()
	claims := Claims{
		UserID: userID,
		Role:   role,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   strconv.FormatInt(userID, 10),
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(ttl)),
		},
	}
	t := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return t.SignedString(secret)
}

func ParseUserToken(secret []byte, tokenStr string) (*Claims, error) {
	t, err := jwt.ParseWithClaims(tokenStr, &Claims{}, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method")
		}
		return secret, nil
	})
	if err != nil {
		return nil, err
	}
	claims, ok := t.Claims.(*Claims)
	if !ok || !t.Valid {
		return nil, fmt.Errorf("invalid token")
	}
	return claims, nil
}
