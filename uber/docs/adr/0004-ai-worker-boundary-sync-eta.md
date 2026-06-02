# ADR 0004: ai-worker 境界 — 同期 REST + 共有トークン + graceful degradation

## ステータス

Accepted (2026-06-02)

## コンテキスト

ADR 0001-0003 で「H3 cell index / 二者間 state machine / per-cell matcher goroutine」を Go backend 内に閉じた形で確立した。Phase 4-2 で **ETA (到着見込み) と需要予測 (surge の素地)** を加えるにあたり、リポジトリ方針 (CLAUDE.md「スタックの役割」) では **AI・予測・ランキングは Python (ai-worker)** に置く。よって Go backend と Python ai-worker の **境界をどう引くか**が論点になる。

決めるべきは 3 つ:

1. **呼び出しタイミング (依存方向)** — ETA を trip 要求の hot path (`POST /trips`) で同期に取るか、後追いで取るか、そもそも core に絡めないか
2. **プロトコル** — 同期 REST / 非同期キュー / gRPC のどれにするか
3. **ai-worker 障害時の挙動** — ai-worker が落ちている / 遅い / エラーのとき配車フローをどうするか

本リポ固有の制約:

- **ローカル完結方針**: ai-worker は外部 ML / 地図 API を使わず deterministic な mock (haversine 距離 + cell ハッシュ) を返す。実 ML への差し替え余地だけ残す。
- **ETA / surge は "付加価値" であって core invariant ではない**。配車そのもの (matching・state machine・compare-and-set) は ai-worker が落ちても **止めてはならない**。rider が ETA を見られないのは degrade で許容できるが、trip が作れないのは許容できない。
- 発生レートは低頻度 (trip 要求ごとに 1 回)。ETA は副作用のない read-only。

既存プロジェクトの蓄積: discord backend (Go) は `callSummarize` で ai-worker を **同期 REST + `X-Internal-Token` + 失敗時 degrade** で呼ぶ。shopify / perplexity でも「内部 trusted ingress (REST + 共有トークン)」「graceful degradation」を `docs/operating-patterns.md` に確立済み。uber はこれを **Go の `net/http` client で地理空間 ETA に適用** する位置づけ。

## 決定

**ETA は `POST /trips` の hot path で ai-worker `POST /eta` を同期 REST 呼び出しし、`X-Internal-Token` の trusted ingress とする。ai-worker 不在 / 遅延 (2s timeout) / 非2xx / decode 失敗はすべて `eta_seconds=null` に degrade し、trip 作成は止めない。** 需要予測は `GET /demand` から `POST /demand-forecast` を同様に呼び、degrade 時は中立値 (surge=1.0) を返す。

- 構成要素 1: **`internal/ai` パッケージに client を隔離** — `Client{BaseURL, Token, HTTP}` + `ETA()` / `DemandForecast()`。境界を 1 箇所に集約し、handler から HTTP の詳細を隠す
- 構成要素 2: **degrade は呼び出し側の責務** — client は error を返すだけ。`AI_WORKER_URL` 未設定なら `Enabled()==false` / `ErrDisabled` を返し、handler が `eta=null` を選ぶ。`*Client` は nil レシーバ安全 (未注入の test 経路でも degrade)
- 構成要素 3: **matcher への enqueue を ETA call より前に実行** — ai-worker の RTT が **matching を遅延させない**。遅れるのは rider への 201 応答だけ (ADR 0003 の per-cell matcher は ETA を知らない)
- 構成要素 4: **`X-Internal-Token`** — ai-worker は token を要求 (defense-in-depth)。backend の `AI_INTERNAL_TOKEN` と ai-worker の `INTERNAL_TOKEN` を一致させる。discord ai-worker と同形
- 構成要素 5: **timeout 2s** — hot path に乗る同期 call の上限。client 自体は 3s の `http.Client.Timeout`、handler 側で 2s の `context` を被せる二重防御

## 検討した選択肢

### 1. `POST /trips` で同期 + graceful degradation ← 採用

- rider に trip 要求と同時に見積もり ETA を返せる (UX が良い)
- 境界が 1 リクエスト内で完結し、追跡・テストが容易 (mock server を注入して 201 の `eta_seconds` を assert できる)
- ai-worker 障害が trip 作成に波及しない (degrade で吸収)
- 欠点: trip 作成 latency に ai-worker RTT が乗る → matcher enqueue を先に済ませて matching への影響は消す

### 2. 後追い (別 endpoint / WS push)

- 利点: trip 作成の hot path が ai-worker から完全に独立、最速で 201 を返せる
- 欠点: rider が ETA を見るのに 2 手目 (poll / WS) が要る。呼び出し点が増え、WS プロトコルに ETA メッセージを足す複雑さが乗る。低頻度・read-only な ETA にはオーバースペック

### 3. 完了時 fare のみ ai-worker

- 利点: ai-worker を hot path から完全排除、結合最小
- 欠点: ETA という rider 向け価値が出ず、Go↔Python 境界の学習対象 (同期境界 + degradation) が痩せる。本フェーズの狙いから外れる

### プロトコル: REST 同期 を採用

- queue (Solid Queue 的) は zoom/shopify で既習。低頻度・同期見積もり・read-only な ETA には不適 (結果を待てない)
- gRPC は依存追加 (proto / コード生成) になり、ローカル完結・最小構成方針に反する
- REST 同期は discord で実績があり、`net/http` 標準だけで済む

## 採用理由

- **学習価値**: Go の `net/http` client で **trusted ingress (共有トークン) + graceful degradation** を実装し、Rails (shopify webhook) / Python の同パターンと言語をまたいで対比できる。`operating-patterns.md` の知見を Go で再現する素材
- **アーキテクチャ妥当性**: 実プロダクトでも「ETA / surge は別サービス、可用性が落ちても core 取引は継続」は定石。core invariant (配車) と付加価値 (ETA) を可用性要件で分離する設計
- **責務分離**: HTTP の詳細を `internal/ai` に隔離。handler は `Enabled()` と error だけ見る。ai-worker は DB を持たず、backend が body で座標 / cell を渡す
- **将来の拡張性**: mock を実 ML / 実地図 ETA に差し替え可能。surge を実際に fare へ反映する / ai 結果をキャッシュする / 拡大検索の候補スコアリングに使う、は派生 ADR

## 結果 / トレードオフ

- trip 作成 latency に最大 2s (timeout) が乗りうる。matcher enqueue は先行するので **matching latency は不変**、rider への 201 だけが遅れる
- ETA は副作用のない read-only なので at-least-once / 冪等性の考慮は不要 (zoom / shopify の結果テーブル UNIQUE とは非対称)
- ai-worker は deterministic mock。同じ座標 → 同じ ETA、同じ cell → 同じ surge。テストが安定する反面、実需要は反映しない (mock であることを README / architecture に明記)
- **スコープ外 (派生 ADR 候補)**: surge を fare に反映 / ETA・需要のキャッシュ / 実 ML / 拡大検索スコアへの利用

## 関連

- ADR 0001 (H3 cell index) — `demand-forecast` の key は H3 cell
- ADR 0002 / 0003 — ETA は state machine / matcher の外側の付加情報
- `docs/operating-patterns.md` — 内部 trusted ingress / graceful degradation
