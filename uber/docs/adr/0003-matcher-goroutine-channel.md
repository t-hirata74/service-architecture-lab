# ADR 0003: per-H3-cell matcher goroutine + channel オファー

## ステータス

Accepted (2026-05-17)

## コンテキスト

ADR 0001 で「H3 cell を sharding キーとした in-memory index」を採用し、ADR 0002 で「compare-and-set で trip / driver の status を進める」を確立した。残る論点は **「マッチングをどう並行に走らせるか」**:

- trip request の発生レートは都市規模で 100-1000 req/s 程度 (本リポではローカルなので 1 req/s 規模だが、設計は実プロダクション規模を意識する)
- driver の位置更新は 4-10s に 1 回 × N driver
- ある trip の matching と別 trip の matching は **異なる cell であれば独立に進めて良い**
- 同一 cell 内では **idle driver の取り合い** が起きるので、何らかのシリアル化が必要

候補のパターン:

1. **per-trip goroutine**: trip 要求ごとに 1 goroutine、ドライバを直接 SELECT
2. **単一 matcher goroutine**: 全 trip を 1 つの goroutine が直列処理
3. **per-cell matcher goroutine**: H3 cell ごとに 1 つの常駐 goroutine、その cell に着信する trip をシリアルに処理
4. **DB polling**: matcher は走らず、driver が `SELECT FOR UPDATE SKIP LOCKED` で trip を引き受ける

加えて「**offer の届け方**」も決める必要がある:

- A: matcher がドライバの WS connection に直接書き込む (matcher と WS が同一プロセスなので可)
- B: matcher が `driver_offers` テーブルに INSERT、driver の WS poller が pickup する
- C: matcher が driver-specific channel に送信、WS goroutine が channel から読み出す

discord で確立した **「single goroutine が map state を専有、channel で IPC」** パターンを地理空間版に拡張するのが本 ADR の中心テーマ。

## 決定

**H3 cell ごとに matcher goroutine を 1 つ常駐させ、`map[H3Cell]*Matcher` を `HubRegistry` のような registry で管理。trip request は `matcher.requests <- TripRequest{}` で投入、matcher が cell + KRing(2) から候補ドライバを並べ、driver の `offers chan` に offer を送る。driver は WS から `accept / reject` を返し、matcher が compare-and-set で確定する。**

- 構成要素 1: **`type Matcher struct { cell H3Cell; requests chan TripRequest; idleDrivers map[DriverID]*driverState; ... }`** — cell 内の state は matcher goroutine 専有 (mutex なし、discord ADR 0002 と同形)
- 構成要素 2: **`type CellRegistry struct { cells sync.Map[H3Cell]*Matcher }`** — 着信した trip の cell から matcher を引いて投入
- 構成要素 3: **lazy 生成 + 当面停止しない** — cell に最初の trip / driver が到着したときに matcher 生成、停止は派生 ADR (inactive cell の lazy 停止)
- 構成要素 4: **offer 経路は C** — `driver.offers chan Offer` に送信、driver の WS goroutine が channel から読んで WS frame として書き出す。non-blocking send + drop (discord と同方針)
- 構成要素 5: **offer タイムアウトは 10s**。matcher は `select { case ack := <-acceptCh: ...; case <-time.After(10*time.Second): tryNextDriver() }`
- 構成要素 6: **拡大検索**: 初期 KRing(2) で候補が 0 なら KRing(4)、最終的に 30s で `no_driver_found` キャンセル

### 構造

```
HTTP POST /trips
    │
    ▼
backend                 cell = h3.LatLngToCell(lat, lng, 9)
    │                   trip := db.Insert(...)
    ▼
CellRegistry.Get(cell) ──► Matcher (cell=h3_A) goroutine
    │                       │
    │                       ▼
    │                   select {
    │                     case req := <-m.requests:
    │                       candidates := m.candidates(req.cell, ring=2)
    │                       for d := range candidates:
    │                         d.offers <- Offer{trip_id, expire_at}
    │                         select {
    │                           case ack := <-acceptCh:
    │                             ok := db.CompareAndSet(driver, idle→matched)
    │                             if ok: notify rider; break
    │                           case <-time.After(10s):
    │                             continue
    │                         }
    │                     case pos := <-m.positionUpdates:
    │                       m.idleDrivers[pos.driverID] = ...
    │                   }
    │
    ▼
driver WS goroutine ─── select {
                         case offer := <-driver.offers:
                           ws.WriteJSON(offer)  // non-blocking
                         case incoming := <-wsReader:
                           switch incoming.op { ... }
                       }
```

### shard 化方針 (派生 ADR 候補)

- 当面 single process で全 cell の matcher を持つ。1 都市 1 万 driver × res 9 ≈ 数百 cell ≈ 数百 goroutine = 余裕
- 複数都市 / 複数リージョンになったら **都市単位で process を分け、cell → process の routing を上位で持つ**。本 ADR ではスコープ外

## 検討した選択肢

### 1. per-cell matcher goroutine + channel offer ← 採用

- 利点: cell 内 state を matcher 専有、**mutex 不要**
- 利点: 異なる cell の matching が **真に独立** に走る (Go scheduler が分散実行)
- 利点: discord ADR 0002 の「single goroutine + select pattern」を地理空間に拡張する同形構造、**コードが対比しやすい** (学習価値)
- 利点: offer の届け方を channel に閉じることで **WS write の責務が WS goroutine 1 箇所** に集約 (discord ADR と同方針)

### 2. per-trip goroutine

- 利点: 実装が直線的、各 goroutine が短命でリソース漏れリスクが低い
- 欠点: **同一ドライバの取り合い** で goroutine 間が DB round trip でしか同期できない → compare-and-set は ADR 0002 で扱えるが、**SQL 負荷が比例増加**
- 欠点: cell 内に「matching 待ち trip の優先順位 (FIFO / 距離順)」を持たせにくい
- 欠点: discord で確立した「state は goroutine 専有」原則と整合しない

### 3. 単一 matcher goroutine

- 利点: 実装が最小
- 欠点: **全 trip がシリアル化** されて並列性が出ない、N cell × 10 trip/s で詰まる
- 欠点: 都市レベルの sharding に発展する道筋が消える

### 4. DB polling (driver が SKIP LOCKED で取りに来る)

- 利点: matcher プロセスが要らない、driver client から polling だけで完結
- 欠点: **driver 側の遅延** が直接マッチング遅延になる (polling 周期 = ~1s)
- 欠点: driver が「自分から近い trip を pickup する」設計だと **遠い trip まで毎回 SELECT** することになる
- 欠点: matcher 側の意思 (「この trip にこの driver を当てる」) が表現しづらい

### offer 経路 B (driver_offers テーブル)

- 利点: WS が切断していても offer が DB に残る
- 欠点: offer は短寿命 (10s) なので DB に書く必要が薄い
- 欠点: driver の WS poll が 1s 単位で SELECT を打つ → 不要な DB 負荷

## 採用理由

- **学習価値**: discord の per-guild Hub を **per-cell matcher に置き換える** ことで、Go の同じ並行 pattern が **テキスト fan-out vs 地理空間マッチング** の 2 用途に適用できることが ADR として残る
- **アーキテクチャ妥当性**: 実 Uber も「city / region 単位の分割 + cell 単位 matcher」設計を発表している (Uber Engineering blog の dispatch 論文)
- **責務分離**: matcher = 判断のみ / WS goroutine = I/O のみ / DB = 永続化 + 競合解決。**3 層が channel と DB の単一インタフェースで疎結合**
- **将来の拡張性**: shard 化 / cell の lazy 停止 / 拡大検索のリトライ戦略 / surge pricing は **matcher の中に閉じて追加できる**

## 却下理由

- **per-trip goroutine**: 同一 cell 内の競合を SQL 任せにすると、SQL 負荷が線形に増える
- **単一 matcher**: 並列性が出ない、shard 化への発展余地が無い
- **DB polling**: driver 側 polling の遅延 + 不要 SQL 負荷
- **offer DB 経由**: 短寿命 offer に DB を経由させるコストが正当化できない

## 引き受けるトレードオフ

- **goroutine 数 = cell 数**: lazy 生成だが停止しないので、長時間運用で **使われない cell の goroutine が滞留** する可能性。派生 ADR で扱う (例: 10 分間 trip も driver もない cell は停止)
- **matcher プロセス再起動でメモリ消失**: in-memory state (idle driver の cell 所属、進行中 offer のタイムアウト残り) は再起動で消える。**DB から再構築 + 進行中 trip は cleanup ジョブ** で吸収
- **cell 境界のドライバ**: cell A にいる driver は cell A の matcher にしか属さないので、cell B の trip からは KRing(2) で見えない場合がある。**KRing(2)** を初期半径にする (1.5km 圏) ことで境界を吸収、それでも漏れる場合は拡大検索 (KRing(4))
- **non-blocking send + drop の意味**: driver の `offers` chan が満杯なら drop する。**未着 offer は数秒以内に matcher が次候補に進む** ので機会損失は限定的。重要なのは matcher が ブロックしない こと (discord ADR 0002 と同方針)

## このADRを守るテスト / 実装ポインタ

- `uber/backend/internal/dispatch/matcher.go` — `Matcher.Run(ctx)` の select loop
- `uber/backend/internal/dispatch/registry.go` — `CellRegistry.GetOrCreate(cell)` (sync.Map)
- `uber/backend/internal/dispatch/matcher_test.go` — `-race` フラグ必須、100 trip × 50 driver を 10 cell で並行、**ドライバ二重取得が無いこと** を assertion
- `uber/backend/internal/dispatch/offer_timeout_test.go` — 10s タイムアウトで次候補に進むこと
- `uber/backend/internal/dispatch/no_driver_test.go` — KRing(2) → KRing(4) → no_driver_found の拡大検索が 30s で打ち切られること

## 関連 ADR

- ADR 0001: H3 geospatial index — 本 ADR の sharding キー
- ADR 0002: trip + driver state machine — 本 ADR の matcher が呼び出す compare-and-set
- discord ADR 0001 (single-process Hub / per-guild) — 並行 pattern の対比対象
- discord ADR 0002 (Hub goroutine + channel + non-blocking send) — 同じパターンを地理空間に適用
- ADR 派生候補: shard 化 / inactive cell の lazy 停止 / surge pricing による matcher 動作変更 / cancellation policy / driver no-show
