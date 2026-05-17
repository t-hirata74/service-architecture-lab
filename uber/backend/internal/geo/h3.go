// Package geo は H3 (hexagonal hierarchical geospatial indexing system) の
// アプリ層向け薄ラッパー。ADR 0001 で採用した resolution 9 を default とする。
//
// 実体は uber/h3-go v4 のバインディング (CGO)。本パッケージで wrapper を切る理由:
//   - 将来 h3-go を別ライブラリに差し替える際の代替点
//   - cell 表現を string (16桁 hex) で持つことを統一 (DB の VARCHAR(16) とアプリ層を揃える)
package geo

import (
	"fmt"

	h3 "github.com/uber/h3-go/v4"
)

// Cell は H3 cell の string 表現 (例: "8a2a1072b59ffff")。
// DB の `drivers.current_h3_cell` / `trips.pickup_h3_cell` (VARCHAR(16)) と互換。
type Cell string

// Encode は緯度経度を resolution の H3 cell に変換する。
func Encode(lat, lng float64, resolution int) (Cell, error) {
	if resolution < 0 || resolution > 15 {
		return "", fmt.Errorf("geo: resolution out of range [0, 15]: %d", resolution)
	}
	c, err := h3.LatLngToCell(h3.NewLatLng(lat, lng), resolution)
	if err != nil {
		return "", fmt.Errorf("geo: encode: %w", err)
	}
	return Cell(c.String()), nil
}

// KRing は cell とその k-ring (k 段までの近傍 cell) を返す。
// ADR 0003 の「初期半径 k=2 で 1.5km 圏、見つからなければ k=4」用途で使う。
func KRing(cell Cell, k int) ([]Cell, error) {
	if k < 0 {
		return nil, fmt.Errorf("geo: k must be >= 0: %d", k)
	}
	// IndexFromString は uint64 を返す。invalid な入力でも値は返るので IsValid で弾く。
	c := h3.Cell(h3.IndexFromString(string(cell)))
	if !c.IsValid() {
		return nil, fmt.Errorf("geo: invalid cell %q", cell)
	}
	neighbors, err := c.GridDisk(k)
	if err != nil {
		return nil, fmt.Errorf("geo: grid disk: %w", err)
	}
	out := make([]Cell, 0, len(neighbors))
	for _, n := range neighbors {
		out = append(out, Cell(n.String()))
	}
	return out, nil
}
