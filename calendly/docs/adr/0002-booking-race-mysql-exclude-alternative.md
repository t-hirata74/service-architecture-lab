# ADR 0002: 同時予約レース防止 — MySQL における `EXCLUDE` 排他制約代替

## ステータス

Accepted（2026-05-07）

## コンテキスト

予約確定 (`POST /bookings`) は **「同じ host・同じ時間帯に 2 件目を絶対に作らない」** という不変条件を要求する。Booking テーブルは `(host_id, start_at, end_at)` を持ち、ADR 0001 で「閉開区間 `[start_at, end_at)`」と決めた。

PostgreSQL なら以下 1 文で済む:

```sql
ALTER TABLE bookings ADD CONSTRAINT no_overlap
  EXCLUDE USING gist (host_id WITH =, tstzrange(start_at, end_at) WITH &&);
```

**MySQL 8 にはこの構文が存在しない**。CHECK 制約や UNIQUE 制約だけでは「区間の重なり禁止」を表現できない (UNIQUE は等値のみ、CHECK は単一行のみ)。

shopify ADR 0003 で確立した **「条件付き UPDATE で原子減算」** の対称形を求めることになる。あちらは「スカラー値 `on_hand >= q` のとき引く」、こちらは「区間の overlap が無いときだけ INSERT」。

スロット取得 (ADR 0001) で空きを表示しても、UI 上で host が同じスロットに 2 ユーザー同時クリックする状況は普通に起きる (calendly の文脈では「team 共有リンク」「公開イベント」)。**at-most-once + 楽観的 UI と組み合わせる**設計が要求される。

## 決定

**「`INSERT ... SELECT WHERE NOT EXISTS` を `with_lock` で囲み、affected_rows == 0 を `BookingConflict` で弾く」** を採用する。

```ruby
# Bookings::CreateService
def call
  Host.lock("FOR UPDATE").find(host_id)  # host 行で advisory lock 風に直列化
  conflict = Booking
    .where(host_id: host_id)
    .where("start_at < ? AND end_at > ?", new_end, new_start)
    .where(status: %w[confirmed pending])
    .exists?
  raise BookingConflict if conflict
  Booking.create!(...)
end
```

要点:

- **host 行を `FOR UPDATE` で lock** することで、同 host への並行 INSERT が直列化される
- overlap 判定は **「左 start < 右 end AND 左 end > 右 start」** (閉開区間の overlap、ADR 0001 と整合)
- `confirmed | pending` のみを衝突対象とする (cancelled は無視)
- 検査 + INSERT は同 transaction 内、commit 時に整合性が確定
- 並行 INSERT で先に lock を取った方が勝ち、後発は `BookingConflict` を返す → controller で 409

DB スキーマ補強:

- `bookings(host_id, start_at, end_at, status)` の **複合 index** で overlap 検索を支える
- `start_at < end_at` を CHECK 制約 (MySQL 8.0.16+ 対応) で fixate

## 検討した選択肢

### 1. host 行 `FOR UPDATE` + overlap 検査 ← 採用

- 利点: 実装が直感的 / SQL レビューがしやすい / overlap 検査の意味が読み取れる
- 利点: zoom の `with_lock` 状態遷移パターンと**同じ流派** (本リポ規律に揃う)
- 欠点: 同 host のスループットが直列化される (CPV: 1 host あたり 秒間数百件はさばけるので学習用途で問題無し)

### 2. `INSERT ... SELECT WHERE NOT EXISTS` (ロック無し)

```sql
INSERT INTO bookings (host_id, start_at, end_at, ...)
SELECT :host, :start, :end, ...
WHERE NOT EXISTS (
  SELECT 1 FROM bookings WHERE host_id = :host
    AND start_at < :end AND end_at > :start
    AND status IN ('confirmed', 'pending')
);
-- affected_rows == 0 なら衝突
```

- 利点: lock を取らないのでスループット高い
- **欠点 (致命的): MySQL の REPEATABLE READ では `WHERE NOT EXISTS` の判定後 INSERT 完了までの間に並行 transaction が同じ判定を通過し、両方 INSERT 成功する**
- SERIALIZABLE まで上げれば防げるが、本リポは他プロジェクトと一貫して REPEATABLE READ なので変えたくない

### 3. unique partial / generated column を使うトリック

- 「同一 host で時間が重なる行が無い」を UNIQUE で表現する gen column を作る…が、**範囲の重複は UNIQUE で表現不能**。等値関数しか UNIQUE は使えない
- 5 分刻みなどでスロット ID を発番すれば近似可能だが、これは ADR 0001 で却下した「静的物理化」と同根の問題が出る

### 4. アプリ層 advisory lock (`SELECT GET_LOCK(...)`)

- 名前付き lock で host_id 単位に serialize
- 利点: 行 lock を取らない / cross-row の制約に使える
- 欠点: lock 名の衝突 / 本リポで他に使われていない (規律が薄い) / DB 移行時の互換性が落ちる
- 欠点: テストでも GET_LOCK が必要 (sqlite で動かない、本リポでは MySQL 統一なので致命傷ではないが)

### 5. SERIALIZABLE 分離レベルで 2 を回す

- 利点: SQL 1 文で済む
- 欠点: 他 transaction まで巻き込んで遅くなる / deadlock 頻度↑ / 本リポ既存と整合しない

## 採用理由

- **学習価値**: 「**MySQL に EXCLUDE が無い時のレース防止 4 択**」を ADR 1 本に整理することは、shopify 在庫減算 (compare-and-decrement) と並ぶ本リポ規律の中核教材になる
- **アーキテクチャ妥当性**: Cal.com の OSS 実装も `prisma.$transaction` + 手動 overlap check で同じ流派
- **責務分離**: 「区間 overlap 不変条件」を `Bookings::CreateService` に閉じ、controller / model からは見えない (zoom `transition_to!` と同じ閉じ方)
- **テスト可能性**: 100 並行スレッドで `CreateService.call` を叩いて、`Booking.count == 1 + BookingConflict.count == 99` を fixate できる (shopify と同じ流儀)

## 却下理由

- 案 2 (NOT EXISTS only): MySQL REPEATABLE READ の意味論で防げないため致命的
- 案 3 (UNIQUE trick): 区間 overlap は UNIQUE で表現不能
- 案 4 (advisory lock): 本リポに先行例なし、規律が薄い
- 案 5 (SERIALIZABLE): 他 transaction を巻き込む副作用が大きすぎる

## 引き受けるトレードオフ

- **同 host スループット**: `FOR UPDATE` で直列化されるが、host あたり 秒間数百を超える着信は本リポの想定外
- **lock の粒度**: host 行を lock するので、**同 host への booking 作成と host 自身の更新も serialize される**。host メタ情報の更新頻度は低いので問題なし
- **キャンセル後の再予約レース**: cancelled な行は overlap 検査で無視するので「キャンセル → すぐ別人が予約」も自然に通る
- **soft conflict**: 公開イベント (1 host × 多人数同時 click) で 1 名以外が 409 を見る → invitee UI 側で「直前に他の方に予約されました」表示が必須 (UX 課題、ADR スコープ外)

## このADRを守るテスト / 実装ポインタ

(実装後に追記)

- `calendly/backend/app/services/bookings/create_service.rb` — `with_lock` + overlap 検査 + INSERT
- `calendly/backend/spec/services/bookings/concurrent_create_spec.rb` — 100 並行 thread で 1 件のみ成立を fixate (shopify ADR 0003 の `concurrent_deduct_spec.rb` と同形)
- `calendly/backend/spec/services/bookings/create_service_spec.rb` — overlap 境界 (隣接 OK / 1 秒重なり NG / cancelled 無視)
- `calendly/backend/db/schema.rb` — `bookings(host_id, start_at, end_at, status)` 複合 index + `start_at < end_at` CHECK

## 関連 ADR

- ADR 0001: availability merge — 「空きを返した直後に競合」が起きる前提を踏まえる
- ADR 0003: RRULE 展開と timezone 永続化 — `start_at` / `end_at` は UTC 保存のため overlap 比較の基準は UTC
- shopify ADR 0003 (cross-project): 条件付き UPDATE での原子減算と同流派
- zoom ADR 0001 (cross-project): `with_lock` で状態遷移を直列化と同流派
- 派生 ADR 候補: 公開イベント (1:N) での invitee UI optimistic display + 409 ハンドリング
