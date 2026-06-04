// Package ai は ai-worker への内部 trusted ingress クライアント (ADR 0004)。
// X-Internal-Token 共有シークレットで認証し、不通/エラーは呼び出し側で degrade させる。
package ai

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"time"
)

type Client struct {
	baseURL string
	token   string
	http    *http.Client
}

func NewClient(baseURL, token string) *Client {
	return &Client{
		baseURL: baseURL,
		token:   token,
		http:    &http.Client{Timeout: 3 * time.Second},
	}
}

type point struct {
	Value float64 `json:"value"`
}

type anomalyResp struct {
	Threshold float64 `json:"threshold"`
}

// DynamicThreshold は /detect-anomaly を呼び mean+k*std の動的閾値を返す。
// ai-worker 不通/エラー時は (0, false) を返し、呼び出し側 (alert engine) は静的閾値で継続する
// (graceful degradation, ADR 0004 / operating-patterns)。
func (c *Client) DynamicThreshold(ctx context.Context, values []float64) (float64, bool) {
	pts := make([]point, len(values))
	for i, v := range values {
		pts[i] = point{Value: v}
	}
	body, err := json.Marshal(map[string]any{"points": pts, "k": 3.0})
	if err != nil {
		return 0, false
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/detect-anomaly", bytes.NewReader(body))
	if err != nil {
		return 0, false
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Internal-Token", c.token)

	resp, err := c.http.Do(req)
	if err != nil {
		return 0, false
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return 0, false
	}
	var out anomalyResp
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return 0, false
	}
	return out.Threshold, true
}
