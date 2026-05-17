package api

import "context"

type ctxKey int

const (
	userIDKey ctxKey = iota + 1
	roleKey
)

func UserIDFromContext(ctx context.Context) (int64, bool) {
	v := ctx.Value(userIDKey)
	if v == nil {
		return 0, false
	}
	id, ok := v.(int64)
	return id, ok
}

func RoleFromContext(ctx context.Context) (string, bool) {
	v := ctx.Value(roleKey)
	if v == nil {
		return "", false
	}
	s, ok := v.(string)
	return s, ok
}
