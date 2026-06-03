// 地図 API を使わないローカル完結方針 (CLAUDE.md) のため、pickup / dropoff /
// driver 待機位置は「名前付きプリセット地点」から選ぶ。
//
// 重要 (ADR 0001 / 0003): matcher は H3 cell 単位でドライバを探すので、rider の
// pickup と driver の go_online が同じ (または隣接 1-ring の) cell に乗っている
// 必要がある。下記は実在する東京の駅座標で、同じ地点を選べば確実に同一 res-9
// cell に入るため、E2E が deterministic になる。

export type Location = {
  id: string;
  label: string;
  lat: number;
  lng: number;
};

export const LOCATIONS: Location[] = [
  { id: "shibuya", label: "渋谷駅", lat: 35.658, lng: 139.7016 },
  { id: "shinjuku", label: "新宿駅", lat: 35.69, lng: 139.7004 },
  { id: "tokyo", label: "東京駅", lat: 35.6812, lng: 139.7671 },
  { id: "shinagawa", label: "品川駅", lat: 35.6285, lng: 139.7387 },
  { id: "ikebukuro", label: "池袋駅", lat: 35.7295, lng: 139.7109 },
];

export function locationById(id: string): Location | undefined {
  return LOCATIONS.find((l) => l.id === id);
}

// lat/lng から一番近いプリセット名を引く (offer 表示用の人間可読ラベル)。
// 一致しなければ座標をそのまま返す。
export function nearestLabel(lat: number, lng: number): string {
  let best: { label: string; d: number } | null = null;
  for (const l of LOCATIONS) {
    const d = (l.lat - lat) ** 2 + (l.lng - lng) ** 2;
    if (best === null || d < best.d) best = { label: l.label, d };
  }
  // 0.0005^2 ≈ 同一地点とみなす閾値
  if (best && best.d < 2.5e-7) return best.label;
  return `${lat.toFixed(4)}, ${lng.toFixed(4)}`;
}
