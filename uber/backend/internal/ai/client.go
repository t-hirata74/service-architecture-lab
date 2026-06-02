// Package ai は ai-worker (FastAPI) への薄い HTTP クライアント。
//
// 境界の方針は ADR 0004:
//   - backend → ai-worker は同期 REST + 共有トークン (X-Internal-Token) の trusted ingress。
//   - ai-worker 不在 / 遅延 / エラーは呼び出し側で graceful degradation として吸収し、
//     trip フロー (POST /trips) は止めない。ここでは error を返すだけで、握り潰しは呼び出し側の責務。
//
// discord backend の callSummarize と同形だが、boundary を学習対象として独立パッケージに切り出す。
package ai

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// ErrDisabled は AI_WORKER_URL 未設定時に返る。呼び出し側は「静かに degrade」として扱う
// (本物の障害ではないので warn ログを出さない判断材料になる)。
var ErrDisabled = errors.New("ai-worker not configured")

// defaultTimeout は同期 call が trip 作成 latency に乗る上限 (ADR 0004 のトレードオフ)。
const defaultTimeout = 3 * time.Second

const maxRespBytes = 1 << 20

type Client struct {
	BaseURL string
	Token   string
	HTTP    *http.Client
}

// NewClient は baseURL が空なら Enabled()==false のクライアントを返す
// (degrade 経路を分岐レスにするため nil ではなく無効クライアントを返す)。
func NewClient(baseURL, token string) *Client {
	return &Client{
		BaseURL: strings.TrimSuffix(strings.TrimSpace(baseURL), "/"),
		Token:   strings.TrimSpace(token),
		HTTP:    &http.Client{Timeout: defaultTimeout},
	}
}

// Enabled は nil レシーバでも安全 (Handler.AI が未注入のときの呼び出しを許す)。
func (c *Client) Enabled() bool { return c != nil && c.BaseURL != "" }

// ─── /eta ─────────────────────────────────────────────────────────────────--

type ETARequest struct {
	PickupLat  float64 `json:"pickup_lat"`
	PickupLng  float64 `json:"pickup_lng"`
	DropoffLat float64 `json:"dropoff_lat"`
	DropoffLng float64 `json:"dropoff_lng"`
}

type ETAResult struct {
	ETASeconds     int `json:"eta_seconds"`
	DistanceMeters int `json:"distance_meters"`
}

func (c *Client) ETA(ctx context.Context, req ETARequest) (ETAResult, error) {
	var out ETAResult
	if err := c.postJSON(ctx, "/eta", req, &out); err != nil {
		return ETAResult{}, err
	}
	return out, nil
}

// ─── /demand-forecast ───────────────────────────────────────────────────────

type DemandForecastRequest struct {
	H3Cell string `json:"h3_cell"`
}

type DemandForecastResult struct {
	H3Cell          string  `json:"h3_cell"`
	DemandIndex     float64 `json:"demand_index"`
	SurgeMultiplier float64 `json:"surge_multiplier"`
}

func (c *Client) DemandForecast(ctx context.Context, req DemandForecastRequest) (DemandForecastResult, error) {
	var out DemandForecastResult
	if err := c.postJSON(ctx, "/demand-forecast", req, &out); err != nil {
		return DemandForecastResult{}, err
	}
	return out, nil
}

// ─── internal ─────────────────────────────────────────────────────────────--

func (c *Client) postJSON(ctx context.Context, path string, body, out any) error {
	if !c.Enabled() {
		return ErrDisabled
	}
	buf, err := json.Marshal(body)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.BaseURL+path, bytes.NewReader(buf))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if c.Token != "" {
		req.Header.Set("X-Internal-Token", c.Token)
	}
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return fmt.Errorf("ai-worker %s: status %d", path, resp.StatusCode)
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, maxRespBytes)).Decode(out); err != nil {
		return fmt.Errorf("ai-worker %s: decode: %w", path, err)
	}
	return nil
}
