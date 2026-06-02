package ai

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestETASuccessAndTokenForwarded(t *testing.T) {
	// channel で受け渡すことで test goroutine と server handler goroutine の間に
	// happens-before を作る (go test -race で捕捉変数の data race を出さない)。
	tokenCh := make(chan string, 1)
	pathCh := make(chan string, 1)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		tokenCh <- r.Header.Get("X-Internal-Token")
		pathCh <- r.URL.Path
		var body ETARequest
		_ = json.NewDecoder(r.Body).Decode(&body)
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(ETAResult{ETASeconds: 120, DistanceMeters: 500})
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "tok-123")
	res, err := c.ETA(context.Background(), ETARequest{
		PickupLat: 37.78, PickupLng: -122.41, DropoffLat: 37.79, DropoffLng: -122.40,
	})
	if err != nil {
		t.Fatalf("ETA: %v", err)
	}
	if res.ETASeconds != 120 || res.DistanceMeters != 500 {
		t.Fatalf("unexpected result: %+v", res)
	}
	if got := <-tokenCh; got != "tok-123" {
		t.Fatalf("token not forwarded: %q", got)
	}
	if got := <-pathCh; got != "/eta" {
		t.Fatalf("unexpected path: %q", got)
	}
}

func TestDisabledClientReturnsErrDisabled(t *testing.T) {
	c := NewClient("", "tok")
	if c.Enabled() {
		t.Fatal("expected Enabled()==false for empty URL")
	}
	if _, err := c.ETA(context.Background(), ETARequest{}); err != ErrDisabled {
		t.Fatalf("want ErrDisabled, got %v", err)
	}
}

func TestNilClientEnabledIsSafe(t *testing.T) {
	var c *Client
	if c.Enabled() {
		t.Fatal("nil client must report disabled")
	}
}

func TestNon2xxReturnsError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "")
	if _, err := c.ETA(context.Background(), ETARequest{}); err == nil {
		t.Fatal("expected error on 401")
	}
}

func TestContextTimeoutPropagates(t *testing.T) {
	// handler は release されるまでブロックし、client 側の context timeout を発火させる。
	// r.Context().Done() に依存すると httptest では client 切断が伝播せず Close() が
	// 無限待ちする (CI で 10 分 timeout を踏んだ)。release チャネルで明示的に解放する。
	// defer は LIFO なので close(release) → srv.Close() の順に走り、handler を解放してから Close。
	release := make(chan struct{})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		<-release
	}))
	defer srv.Close()
	defer close(release)

	c := NewClient(srv.URL, "")
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	if _, err := c.ETA(ctx, ETARequest{}); err == nil {
		t.Fatal("expected timeout error")
	}
}

func TestDemandForecast(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(DemandForecastResult{
			H3Cell: "abc", DemandIndex: 0.5, SurgeMultiplier: 1.5,
		})
	}))
	defer srv.Close()

	c := NewClient(srv.URL, "")
	res, err := c.DemandForecast(context.Background(), DemandForecastRequest{H3Cell: "abc"})
	if err != nil {
		t.Fatalf("DemandForecast: %v", err)
	}
	if res.SurgeMultiplier != 1.5 || res.H3Cell != "abc" {
		t.Fatalf("unexpected: %+v", res)
	}
}
