package api

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"strconv"
	"testing"
	"time"

	"github.com/go-sql-driver/mysql"

	"github.com/hiratatomoaki/service-architecture-lab/uber/backend/internal/store"
)

// 統合テストは UBER_TEST_DB env が設定されているときだけ走る。
// dispatch package の integration_test.go と同じ pattern。
func openTestServer(t *testing.T) (*httptest.Server, *store.Store) {
	t.Helper()
	dsn := os.Getenv("UBER_TEST_DB")
	if dsn == "" {
		t.Skip("UBER_TEST_DB not set, skipping integration test")
	}
	mc, err := mysql.ParseDSN(dsn)
	if err != nil {
		t.Fatalf("parse dsn: %v", err)
	}
	mc.MultiStatements = false
	db, err := sql.Open("mysql", mc.FormatDSN())
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	if err := db.Ping(); err != nil {
		t.Fatalf("ping: %v", err)
	}
	t.Cleanup(func() { _ = db.Close() })

	st := &store.Store{DB: db}
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	h := NewHandler(log, st, []byte("test-secret-do-not-use-in-prod"))
	srv := httptest.NewServer(h.Routes())
	t.Cleanup(srv.Close)
	return srv, st
}

func doJSON(t *testing.T, method, url, token string, body any) (int, map[string]any) {
	t.Helper()
	var reqBody io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("marshal body: %v", err)
		}
		reqBody = bytes.NewReader(b)
	}
	req, err := http.NewRequest(method, url, reqBody)
	if err != nil {
		t.Fatalf("new request: %v", err)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("http: %v", err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	out := map[string]any{}
	if len(raw) > 0 {
		_ = json.Unmarshal(raw, &out)
	}
	return resp.StatusCode, out
}

func uniqueEmail(t *testing.T, prefix string) string {
	t.Helper()
	return prefix + "-" + strconv.FormatInt(time.Now().UnixNano(), 10) + "@test.local"
}

// signup -> /me が role 含めて返ってくる + drivers 行が作られる
func TestIntegration_RegisterRider_Then_Me(t *testing.T) {
	srv, _ := openTestServer(t)

	email := uniqueEmail(t, "rider")
	code, body := doJSON(t, "POST", srv.URL+"/auth/register", "", map[string]any{
		"email":        email,
		"password":     "rider-pw-12345",
		"role":         "rider",
		"display_name": "Test Rider",
	})
	if code != http.StatusCreated {
		t.Fatalf("register: status %d body %v", code, body)
	}
	token, _ := body["token"].(string)
	if token == "" {
		t.Fatal("token empty")
	}

	code, body = doJSON(t, "GET", srv.URL+"/me", token, nil)
	if code != http.StatusOK {
		t.Fatalf("/me: status %d body %v", code, body)
	}
	user, _ := body["user"].(map[string]any)
	if user["email"] != email {
		t.Errorf("/me email = %v, want %s", user["email"], email)
	}
	if user["role"] != "rider" {
		t.Errorf("/me role = %v, want rider", user["role"])
	}
}

func TestIntegration_RegisterDriver_CreatesDriverRow(t *testing.T) {
	srv, st := openTestServer(t)

	email := uniqueEmail(t, "driver")
	code, body := doJSON(t, "POST", srv.URL+"/auth/register", "", map[string]any{
		"email":        email,
		"password":     "driver-pw-12345",
		"role":         "driver",
		"display_name": "Test Driver",
	})
	if code != http.StatusCreated {
		t.Fatalf("register: status %d body %v", code, body)
	}
	user := body["user"].(map[string]any)
	uid := int64(user["id"].(float64))

	d, err := st.DriverByUserID(t.Context(), uid)
	if err != nil {
		t.Fatalf("DriverByUserID: %v", err)
	}
	if d.Status != "offline" {
		t.Errorf("driver status = %s, want offline", d.Status)
	}
}

// 同じ email で 2 回 register すると 2 回目は 409
func TestIntegration_DuplicateEmail_409(t *testing.T) {
	srv, _ := openTestServer(t)

	email := uniqueEmail(t, "dup")
	body := map[string]any{
		"email":        email,
		"password":     "rider-pw-12345",
		"role":         "rider",
		"display_name": "Dup User",
	}
	if code, _ := doJSON(t, "POST", srv.URL+"/auth/register", "", body); code != http.StatusCreated {
		t.Fatalf("first register: %d", code)
	}
	if code, _ := doJSON(t, "POST", srv.URL+"/auth/register", "", body); code != http.StatusConflict {
		t.Errorf("second register: status = %d, want 409", code)
	}
}

// register したあと、login で同じ token が引ける
func TestIntegration_LoginFlow(t *testing.T) {
	srv, _ := openTestServer(t)

	email := uniqueEmail(t, "login")
	pw := "login-pw-12345"

	code, _ := doJSON(t, "POST", srv.URL+"/auth/register", "", map[string]any{
		"email":        email,
		"password":     pw,
		"role":         "rider",
		"display_name": "Login User",
	})
	if code != http.StatusCreated {
		t.Fatalf("register: %d", code)
	}

	// 正常 login
	code, body := doJSON(t, "POST", srv.URL+"/auth/login", "", map[string]any{"email": email, "password": pw})
	if code != http.StatusOK {
		t.Fatalf("login: %d", code)
	}
	if _, ok := body["token"].(string); !ok {
		t.Error("login response missing token")
	}

	// 間違ったパスワードで 401
	code, _ = doJSON(t, "POST", srv.URL+"/auth/login", "", map[string]any{"email": email, "password": "WRONG"})
	if code != http.StatusUnauthorized {
		t.Errorf("wrong pw login: status = %d, want 401", code)
	}

	// 存在しない email で 401
	code, _ = doJSON(t, "POST", srv.URL+"/auth/login", "", map[string]any{"email": "no-such@test.local", "password": pw})
	if code != http.StatusUnauthorized {
		t.Errorf("unknown email login: status = %d, want 401", code)
	}
}

// 不正な role / 短いパスワード / email 形式の validation
func TestIntegration_RegisterValidation(t *testing.T) {
	srv, _ := openTestServer(t)
	base := map[string]any{
		"email":        uniqueEmail(t, "val"),
		"password":     "valid-pw-12345",
		"role":         "rider",
		"display_name": "Valid",
	}
	type tc struct {
		name      string
		mutate    func(map[string]any)
		wantCode  int
	}
	cases := []tc{
		{"role=admin (invalid)", func(b map[string]any) { b["role"] = "admin" }, http.StatusBadRequest},
		{"password too short", func(b map[string]any) { b["password"] = "short" }, http.StatusBadRequest},
		{"no @ in email", func(b map[string]any) { b["email"] = "no-at-sign" }, http.StatusBadRequest},
		{"empty display_name", func(b map[string]any) { b["display_name"] = " " }, http.StatusBadRequest},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			b := map[string]any{}
			for k, v := range base {
				b[k] = v
			}
			b["email"] = uniqueEmail(t, "val") // 衝突回避
			c.mutate(b)
			if code, _ := doJSON(t, "POST", srv.URL+"/auth/register", "", b); code != c.wantCode {
				t.Errorf("status = %d, want %d", code, c.wantCode)
			}
		})
	}
}
