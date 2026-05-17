package geo

import (
	"testing"
)

// TestEncode_TokyoStation: 東京駅 (35.6812, 139.7671) を resolution 9 で encode し、
// 16 桁の hex cell 文字列が返ることを確認する。
func TestEncode_TokyoStation(t *testing.T) {
	cell, err := Encode(35.6812, 139.7671, 9)
	if err != nil {
		t.Fatalf("Encode: %v", err)
	}
	if len(string(cell)) != 15 && len(string(cell)) != 16 {
		t.Fatalf("expected 15-16 hex cell, got %q (len=%d)", cell, len(string(cell)))
	}
}

// TestKRing_Center: k=0 は自分自身 1 件、k=1 は中央 + 6 隣接 = 7 件 (六角形の性質)。
func TestKRing_Center(t *testing.T) {
	cell, err := Encode(35.6812, 139.7671, 9)
	if err != nil {
		t.Fatalf("Encode: %v", err)
	}
	tests := []struct {
		k    int
		want int
	}{
		{0, 1},
		{1, 7},  // 中央 + 6 隣接
		{2, 19}, // 中央 + 6 + 12
	}
	for _, tc := range tests {
		got, err := KRing(cell, tc.k)
		if err != nil {
			t.Fatalf("KRing(k=%d): %v", tc.k, err)
		}
		if len(got) != tc.want {
			t.Errorf("KRing(k=%d): got %d cells, want %d", tc.k, len(got), tc.want)
		}
	}
}

// TestEncode_ResolutionOutOfRange: H3 仕様の 0-15 範囲外は明示的にエラーで返す。
func TestEncode_ResolutionOutOfRange(t *testing.T) {
	if _, err := Encode(35.0, 139.0, -1); err == nil {
		t.Error("expected error for resolution -1")
	}
	if _, err := Encode(35.0, 139.0, 16); err == nil {
		t.Error("expected error for resolution 16")
	}
}
