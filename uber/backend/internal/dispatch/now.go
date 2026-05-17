package dispatch

import "time"

// defaultNow は time.Now() を返す本番用 nowProvider。
// test では別ファイル (_test.go) から差し替える。
func defaultNow() time.Time {
	return time.Now()
}
