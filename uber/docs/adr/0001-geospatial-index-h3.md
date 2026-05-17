# ADR 0001: 地理空間索引は H3 (hexagonal grid) を in-memory で持つ

## ステータス

Accepted (2026-05-17)

## コンテキスト

uber では rider の pickup 地点付近にいる idle ドライバを **数十 ms 以内に複数件取り出す** 必要がある。要件:

- read: 「半径 R メートル以内の idle driver を全部」を 1 リクエストあたり 10〜100 件取りたい
- write: ドライバの WS から 4〜10 秒に 1 回位置が更新される。プロダクションでは 1 都市 1 万ドライバ規模を想定 (本リポではローカルなので 10〜100 ドライバ規模)
- ローカル完結方針 (`docs/service-architecture-lab-policy.md`): 外部マップ API 不使用、Redis 不使用 (Discord ADR 0001 と同方針)
- 学習価値: 「Uber 系がなぜ H3 を採用したか」を ADR で再現することが学習対象そのもの

地理空間索引の候補は (1) Geohash (2) S2 (Google) (3) H3 (Uber) (4) MySQL Spatial Index (R-tree)。「**どの cell index を選ぶか**」と「**索引を MySQL に持つか in-memory に持つか**」の 2 軸が決まれば設計が定まる。

将来のスケール考慮:
- 1 都市内なら in-memory `map[cell][]driverID` で十分 (各 cell の driver は数百以下)
- 複数都市 / 多リージョンになれば shard 化 ADR を派生で起こす

## 決定

**`uber/h3-go` (v4 系) で計算した H3 cell (resolution 9, ≈ 0.1km² 六角形) を key とした in-memory `map[H3Cell][]DriverID`** をマッチング索引として採用する。

- 構成要素 1: **H3 v4 (uber/h3-go)** で `(lat, lng) → cell` 変換、`KRing(cell, k)` で半径展開
- 構成要素 2: **resolution 9** (≈ edge 174m, area 0.1 km²) を都市内ライド配車のデフォルトに固定
- 構成要素 3: 索引本体は **Go process 内の `sync.Map[H3Cell] *cellState`**。`cellState` には matcher channel と driver ID set を持つ
- 構成要素 4: **DB (`drivers.current_h3_cell`) は eventual mirror**。位置更新は in-memory に書いた後、非同期で UPDATE する (4-10s に 1 回)
- 構成要素 5: 永続化要件は「driver 再接続時の最終位置復元」程度なので **強整合を取らない**

resolution 9 を採用する根拠: Uber の公式資料でも近距離マッチングは res 8-9 を使う。res 9 だと 1km 圏 ≈ 30 cell, 5km 圏 ≈ 700 cell。本リポでは res 9 + `KRing(cell, 2)` (1.5km 圏) を初期半径、見つからなければ `k=4` (3km 圏) に拡大する設計を ADR 0003 で扱う。

## 検討した選択肢

### 1. H3 (hexagonal grid) ← 採用

- 利点: **六角形は隣接 cell が 6 個固定** で「角の歪み」が無い (geohash の 8 隣接 + 角度依存の歪みを避けられる)
- 利点: `KRing(cell, k)` で **k-ring 展開が距離単調**。「2 リング = だいたい 350m 圏」のような直感が効く
- 利点: Uber 公式ライブラリ (h3-go v4) が **MIT で公開済み**、CGO なし pure Go バインディングあり (v4 から)
- 利点: 実プロダクション (Uber, Foursquare, lyft) で実績、学習素材として最良
- 欠点: `uber/h3-go` 依存追加 (これは新規依存だが、policy 上「外部 SaaS / マネージドサービス」ではなくただの Go library なので追加可)

### 2. Geohash (base32 prefix encoding)

- 利点: 単純な string、DB で `LIKE 'dr5ru%'` で範囲検索できる、追加 lib 不要 (自前実装でも数十行)
- 欠点: **角度ゆがみ**。赤道近くと極近くで cell の物理サイズが大きく変わる
- 欠点: **隣接 cell の取得が面倒**。同 prefix 内は近いが、prefix の境界 (例: `dr5ru` と `dr5rv`) では地理的に近いのに別 prefix。**境界対策で 8 neighbor cell を毎回計算する必要** がある
- 欠点: 学習価値は低い (Uber は採用していない)

### 3. S2 (Google spherical quad-tree)

- 利点: 球面上の精度が高く、地球全体を扱える。Foursquare / Google Maps で使用
- 利点: Go binding (`golang/geo`) あり
- 欠点: **学習価値が H3 と被るが ADR 価値は下がる** (Uber プロジェクトに S2 を選ぶ理由が薄い)
- 欠点: API が H3 より複雑。`CellID` の bit 操作が必要、k-ring に相当する API が直感的でない

### 4. MySQL Spatial Index (R-tree, `GEOMETRY` 型 + `SPATIAL INDEX`)

- 利点: 索引が DB に持てる → backend のメモリ状態を気にしなくて良い、再起動で消えない
- 利点: 既存 MySQL を使い回せる、追加 lib 不要
- 欠点: **高頻度 update に弱い**。R-tree は insert/update が O(log n × 平均深さ) で、1 万 driver × 5s 更新 = 2000 write/s で B-tree 書き換えが負荷。本リポではローカルなので 10 driver 規模だが、**実プロダクション設計の学習が目的** なので「高頻度 update + low-latency read」を MySQL に押し付ける設計は学習対象として不適切
- 欠点: 半径検索は `ST_Distance_Sphere` で書けるが、結果の **ソート + LIMIT** で full sort になりやすく、index が効くケースが限定的
- 欠点: matcher goroutine (ADR 0003) と index が別プロセスなので、**マッチング判断のたびに DB round trip** が要る (in-memory なら map lookup で O(1))

## 採用理由

- **学習価値**: Uber 系の「H3 採用」が本プロジェクトの存在理由そのもの。H3 を採用せずに別の index で書くと Uber を再現する意味が薄まる
- **アーキテクチャ妥当性**: 実 Uber も H3 で in-memory index + DB eventual mirror。同形を取れる
- **責務分離**: DB は **永続化責務だけ** に絞る。matcher / index は Go process 内に閉じる。discord ADR 0001 の「Redis を使わない単一プロセス」と思想は同形
- **将来の拡張性**: shard 化 (multi-process + 都市単位分割) は派生 ADR で扱える。H3 cell は都市境界に依存しない uniform grid なので shard キーとして自然

## 却下理由

- **Geohash**: 角度歪み + 隣接 cell の境界処理が煩雑。学習価値が低い
- **S2**: Uber プロジェクトで S2 を選ぶと「なぜ H3 でない」を ADR で釈明する必要があり、学習方向が反転する
- **MySQL Spatial Index**: 高頻度 update + low-latency read を DB に押し付ける設計は学習対象として不適切。matcher goroutine とのデータローカリティも悪い

## 引き受けるトレードオフ

- **新規依存 (`uber/h3-go`)**: 追加するが pure Go library。policy で禁止される「外部 SaaS / マネージドサービス」ではない。Go module で固定する
- **in-memory state の re-build コスト**: backend 再起動時、DB から `drivers.current_h3_cell` を読み出して再構築する必要がある。**1 回ぶんの DB scan で済む** ので許容
- **driver position の eventual consistency**: in-memory が真、DB は遅延 mirror。**「数秒前の位置」が DB に残るケース** はあるが、マッチングは in-memory 側を信頼する。再起動直後の数秒だけ古い位置でマッチする可能性
- **resolution 固定 (9)**: 都市内ライドだけを想定。郊外 / 高速移動には res 8 のほうが効率的だが、それは派生 ADR (例: trip 種別ごとの resolution 切り替え) で扱う

## このADRを守るテスト / 実装ポインタ

- `uber/backend/internal/geo/h3index.go` — `Encode(lat, lng) Cell`, `KRing(cell, k) []Cell`
- `uber/backend/internal/dispatch/index.go` — `cellIndex sync.Map[H3Cell]*cellState` (実装は ADR 0003 と並走)
- `uber/backend/internal/geo/h3index_test.go` — 「東京駅と銀座が `k=2` で含まれる」「赤道直下と東京で cell area が H3 規約通り均一」のような不変条件試験

## 関連 ADR

- ADR 0002: 配車 state machine — H3 cell 内で matcher が compare-and-set でドライバを取得する
- ADR 0003: per-cell matcher goroutine — 本 ADR で導入した cell を sharding キーに使う
- ADR 派生候補: shard 化 (multi-process + 都市単位) / 動的 resolution 切替 / driver position の outbox 永続化
