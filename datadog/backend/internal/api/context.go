package api

import "context"

type ctxKey int

const userIDKey ctxKey = iota

func withUserID(ctx context.Context, id int64) context.Context {
	return context.WithValue(ctx, userIDKey, id)
}

// UserIDFrom は JWT middleware が載せた user_id を取り出す。
func UserIDFrom(ctx context.Context) (int64, bool) {
	id, ok := ctx.Value(userIDKey).(int64)
	return id, ok
}
