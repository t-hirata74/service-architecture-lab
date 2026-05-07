# ADR 0003: RRULE 展開と timezone 永続化

## ステータス

Accepted（2026-05-07）

## コンテキスト

calendly の availability_rules は **「毎週月-金 9:00-17:00」** のような recurring で表現される。これを毎回行に物理展開する設計 (ADR 0001 案 4 で却下) は取らないので、**保存形式と展開タイミング**を明確に決める必要がある。

合わせて、本ドメインで最も事故りやすいのが **timezone**。Calendly は host が定義した時間帯 (例: "毎週水曜 14:00 in `Asia/Tokyo`") を、世界中の invitee に各自 TZ で表示するので、**「保存はどの TZ?」「DST 跨ぎはどう扱う?」「展開した瞬間の壁時計は何?」** を曖昧にできない。

参考にする標準は **RFC 5545 (iCalendar)** の `RRULE`。すでに ical 形式の repository (`ice_cube`) が Ruby に存在する。

## 決定

3 つの規律をセットで採用する。

### 規律 1: 「壁時計 + tz_id」で保存、展開時に UTC へ写像

`availability_rules` テーブル:

```ruby
create_table :availability_rules do |t|
  t.references :host, null: false, foreign_key: true
  t.references :event_type, foreign_key: true   # null なら host のグローバルルール
  t.string :rrule, null: false                  # "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR"
  t.time :start_time_of_day, null: false        # 09:00:00 (壁時計)
  t.time :end_time_of_day, null: false          # 17:00:00 (壁時計)
  t.string :tz_id, null: false                  # "Asia/Tokyo" (IANA tz database id)
  t.date :effective_from
  t.date :effective_until
  t.timestamps
end
```

- 「**壁時計 (time_of_day) + tz_id**」で保存する。UTC で `09:00` を保存しない (DST が来ると 09:00 ⇄ 10:00 が動く / host UI で「9:00-17:00」と入力したのに「8:00-16:00」と表示される事故になる)
- IANA tz id (`Asia/Tokyo`, `America/New_York`) を採用する。`+09:00` のような offset string は **DST を表現できない**ので不可

### 規律 2: 展開は **lazy** (取得時に都度) で実装、`bookings.start_at` のみ UTC で物理保存

- `availability_rules` は recurring 文字列のままにし、**`Availability::SlotsService` (ADR 0001) が要求された期間 `[from, to)` に対してその場で展開**
- 展開実装は MVP では Ruby 標準ライブラリ + `tzinfo` で十分 (RRULE のフル仕様は不要、`FREQ=WEEKLY;BYDAY=...` だけサポート)
- 大きくなったら `ice_cube` gem に置き換え。ただし **依存追加は派生 ADR を書いて承認を得る** (CLAUDE.md ルール 2)
- **bookings は `start_at` / `end_at` を UTC `datetime` で保存** (recurring ではなく 1 回限りの確定時刻なので壁時計保存にする意味がない)

### 規律 3: DST 跨ぎは「壁時計を維持する」方針

- 例: ホストが `America/New_York` で「毎週水曜 14:00-15:00」を登録、2026-03-08 に米国 DST 開始 (02:00 → 03:00 にスキップ)
- DST 跨ぎ自体が 14:00 を含まないので、3/4 (DST 前 / `UTC+19:00`) と 3/11 (DST 後 / `UTC+18:00`) の **UTC 上の絶対時刻は変わる**が、**壁時計は両方 14:00 で同じ**
- これは Calendly / Cal.com / Google Calendar 全部の流儀
- 例外: 「DST スキップ (2 月の `02:30` のような存在しない時刻)」と「DST フォールバック (秋に 1:30 が 2 回出現する曖昧時刻)」は **エラーにせず "そのまま壁時計を採用 → tzinfo の `local_to_utc(...,dst: nil)` の挙動に委ねる"** とする (ADR スコープ外、必要なら派生)

## 検討した選択肢

### 規律 1 の代替

- **(A) UTC で保存**: 単純だが DST で壁時計が動く事故あり → 却下
- **(B) `Asia/Tokyo+09:00` のような offset string**: DST を表現できない → 却下
- **(C) 採用案: 壁時計 + tz_id**: Calendly 公式 / Cal.com OSS とも採用

### 規律 2 の代替

- **(A) eager: `effective_from` 以降を window 期間ぶん全行展開して `availability_slots` テーブルに INSERT**
  - 利点: スロット取得が SELECT 1 本
  - 欠点: window 期間設定 (例: 60 日先まで) の更新が走るたびに削除/再生成 / RRULE 変更時の整合性 / 行数爆発 (ADR 0001 案 4 の再来)
- **(C) 採用案: lazy**: `from..to` 窓だけ毎回展開。スループット問題は 派生 ADR で cache 層を検討

### 規律 3 の代替

- **(A) DST 跨ぎは UTC 連続性を維持** (= 壁時計が 14:00 ⇄ 13:00 と動く)
  - 欠点: 「水曜 14:00 の枠なのに 13:00 に予約された」となり UX 破綻
- **(C) 採用案: 壁時計連続性**: Calendly / Google Calendar と同じ流儀

## 採用理由

- **学習価値**: 「**timezone を 1 行で書こうとしない**」「**壁時計と UTC を意識して使い分ける**」「DST 跨ぎの曖昧時刻に向き合う」は、calendar 系プロダクトを離れてもログ集計 / scheduling / 履歴分析で必ず効く一般教材
- **アーキテクチャ妥当性**: Calendly / Cal.com / Google Calendar 全部 (A) UTC 保存ではなく (C) 壁時計 + tz_id 方式
- **責務分離**: 展開ロジックを `Availability::RruleExpansion` (PORO) に閉じる。テストは `Time.zone` を切り替えながら fixate 可能

## 却下理由

- 規律 1 (A) UTC 保存: DST で壁時計がずれる致命傷
- 規律 1 (B) offset string: DST を扱えない
- 規律 2 (A) eager 展開: 行数爆発と更新整合性が学習主旨に見合わない
- 規律 3 (A) UTC 連続性: UX 破綻

## 引き受けるトレードオフ

- **lazy 展開のスループット**: 1 host × 数週間 で問題なし。大規模化 (1 万 host 並列管理画面) は派生 ADR で cache 層を入れて吸収
- **gem 依存**: tzinfo は Rails 標準依存なので追加無し。RRULE フル仕様が必要になったら ice_cube を派生 ADR で
- **DST スキップ / フォールバック の曖昧さ**: 厳密対応は派生 ADR。MVP では tzinfo のデフォルト挙動に委ね、spec で fixate して挙動を「決める」だけ
- **過去の予約と TZ 規則変更**: IANA tz database が更新されて過去の DST 規則が変わったとき、既存 bookings の `start_at` (UTC) は変わらないが「壁時計表示」は揺れる可能性あり (実害は小さく ADR スコープ外)

## このADRを守るテスト / 実装ポインタ

(実装後に追記)

- `calendly/backend/app/services/availability/rrule_expansion.rb` — RRULE 文字列 → `[from, to)` 内の壁時計 occurrences 配列
- `calendly/backend/app/services/availability/local_to_utc.rb` — `wall_time + tz_id` → UTC datetime
- `calendly/backend/spec/services/availability/dst_crossing_spec.rb` — 米国 / EU / 南半球 (シドニー) の DST 跨ぎ で 「壁時計が維持される」 を fixate
- `calendly/backend/spec/services/availability/rrule_expansion_spec.rb` — `FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR` を 4 週間展開して 20 occurrences を fixate

## 関連 ADR

- ADR 0001: availability merge — RRULE 展開を呼び出す側
- ADR 0002: 同時予約レース防止 — bookings.start_at が UTC である前提に依存
- 派生 ADR 候補: 大規模化時の cache 層 / DST 曖昧時刻の厳密ハンドリング / ice_cube への移行
