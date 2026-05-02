# ADR 0004: 引用整合性の検証境界

## ステータス

Accepted（2026-05-01）

## コンテキスト

RAG の synthesize ステージで mock LLM (ai-worker) は出力中に **`[#src_3]` のような引用 marker** を埋めて answer を生成する。
LLM 出力の典型的な失敗モードとして:

- **ハルシネーション**: retrieve 結果に存在しない source を引用する
- **id ずれ**: 引用 id を `src_3` ではなく `src_03`、`#3`、`source 3` のように揺らす
- **passage 外の引用**: 渡した passage と無関係な内容に引用 marker を貼る

がある。本プロジェクトは mock LLM 相手なので "本物のハルシネーション" は出ないが、**「信頼できない出力源 (LLM) と信頼できる境界 (アプリ) をどこに引くか」** を学習対象として正面から扱いたい。

制約:

- ローカル完結 (LLM-as-a-judge による検証ループは導入しない)
- ADR 0001 の決定により、retrieve / extract / synthesize の中間結果は Rails から見えている
- ADR 0003 の決定により、Rails が ai-worker の SSE を proxy する経路上に検証ロジックを置ける
- Citation の永続化 (`citations` テーブル) は **検証通過分だけ** にしたい (audit ログとしての価値)

## 決定

**「Rails 側で再検証する。ai-worker は信頼境界の外側として扱う」** を採用する。

### 検証フロー

1. **入力契約**: Rails が `/synthesize/stream` を呼ぶ際に **`allowed_source_ids: [42, 117, 203, ...]`** を渡す。これは retrieve 結果の `source_id` から組んだ集合
2. **ai-worker 側の自衛**: ai-worker は出力中に `[#src_<source_id>]` 形式の marker を吐く際、`allowed_source_ids` 集合内であることを **assert (warn)** する。違反は処理を止めず log に残す (panic ではなく warn)
3. **Rails 側の最終検証**: SSE proxy 中、各 `event: chunk` の `data.text` を **正規表現 (`/\[#(src_\d+)\]/`)** でスキャン、抽出した marker の `source_id` 部分を `allowed_source_ids` と照合
4. **整合性違反の扱い**:
   - 違反 marker は **本文には残す** (frontend 表示の連続性を保つため)
   - **追加で `event: citation_invalid` data:`{ marker, reason }`** を frontend に通知
   - **`citations` テーブルには insert しない**
5. **整合性 OK の扱い**:
   - `event: citation` data:`{ marker, source_id, chunk_id, valid: true }` を frontend に通知
   - SSE 終了 (`event: done`) で `citations` テーブルに永続化
6. **partial buffering**: chunk の境界で marker が分断される (`[#src_` で chunk 終わり、次 chunk が `3]`) ケースのため、Rails 側で **未確定 tail バッファ**を保持。完全な marker / 改行 / 確定文字までは frontend に流さない

### 信頼境界の図解

```
┌─────────────────────────┐    ┌─────────────────────────┐    ┌──────────────┐
│ ai-worker (untrusted)   │    │ Rails (trusted boundary)│    │ Frontend     │
│ /synthesize/stream      │ ─► │ SSE proxy + validator   │ ─► │ render UI    │
│  - mock LLM             │    │ - 引用 ID 抽出 (regex)  │    │ - typewriter │
│  - allowed_source_ids   │    │ - allowed 集合と照合     │    │ - citation   │
│    を assert (warn)     │    │ - citation 永続化       │    │   highlight  │
└─────────────────────────┘    └─────────────────────────┘    └──────────────┘
```

### 「本文に [?] で残す」案を採らない理由

「不正引用は本文中の marker を `[?]` に置換する」案も検討したが:

- 文脈が壊れる ("(...) 完成した [?]" は人間にも読めない)
- 検証対象は **citation 永続化の有無** であって本文の改変ではない
- frontend は `citation_invalid` を受けて該当 marker を **薄字 / クリック不可** にレンダリングすれば UX 的に十分

→ 本文は素通し、citation テーブルへの永続化のみを境界とする。

## 検討した選択肢

### 1. Rails 側で再検証 ← 採用

- 信頼境界を Rails に置く: 永続化 / 認可と同じ層に検証が集まる
- ai-worker が信頼できなくても citations テーブルは clean
- 欠点: Rails 側で SSE 中にテキストスキャンするコスト (regex は十分軽い)

### 2. ai-worker 内で完結

- 利点: 実装が simple、HTTP 1 ホップ削減
- 欠点: **「LLM が間違うのは ai-worker 内部の出来事」を ai-worker 自身が検証するのは循環**
- 欠点: Rails ↔ ai-worker の責務分離 (ADR 0001) が薄まる
- 欠点: 学習対象 ("信頼できない出力を信頼境界で検証する") が消える

### 3. 検証なし (ai-worker の出力を素通し)

- 利点: 最小実装
- 欠点: ハルシネーション issue を学べない
- 欠点: citations テーブルにゴミが永続化される

### 4. Frontend 側で検証

- 利点: SSE proxy 中のテキスト処理が不要
- 欠点: **citations の永続化は backend 側にしかできない** → 結局 backend に検証ロジックが必要、二重実装になる
- 欠点: 「永続化と検証を同層に置く」原則と整合しない (永続化は Rails / 検証は Frontend という分離は責務として不自然)

### 5. LLM-as-a-judge (別 LLM で fact check)

- 利点: 本物の RAG ではこの方向に進む (Toulmin / SelfCheckGPT 系)
- 欠点: ローカル完結方針からズレる (mock LLM での自検証は循環)
- 欠点: 本 ADR のスコープ ("信頼境界の引き方") を越える、派生 ADR で扱える題材

### 6. 構造化出力 (JSON で chunks と citations を別フィールドに)

- 利点: regex parse が要らない、型安全
- 欠点: SSE のテキスト streaming UX が難しくなる (構造化出力を chunk ごとに送ると JSON が崩れる、`text/event-stream` の中で JSON streaming する複雑さ)
- 欠点: 実 LLM (OpenAI / Anthropic 等) の SSE フォーマットも本文 + tool_use 系イベントの混在型で、本ADR の方向と整合
- → 「インライン marker + Rails 側 regex」の方が本物の LLM streaming と整合

## 採用理由

- **学習価値**: 「信頼できない出力源と信頼境界の置き方」というセキュリティ / アーキテクチャ的に汎用な議題が、コードに具体形で残る
- **アーキテクチャ妥当性**: 永続化 / 認可と同じ場所 (Rails) に検証を集める。境界の数を増やさない原則と整合
- **責務分離**: ai-worker = 計算 (mock LLM)、Rails = 検証 + 永続化、Frontend = 表示。三層の責務が一直線
- **将来の拡張性**: real LLM API (OpenAI / Anthropic) に差し替えてもこの境界は崩れない。むしろ real LLM ではハルシネーションが本当に起きるので価値が増す

## 却下理由

- ai-worker 内検証: 循環、責務分離 / 学習対象とズレる
- 検証なし: citation 整合性の意味が消える
- Frontend 検証: 永続化が backend にある以上、結局 backend で再検証になり二重実装。責務分離としても不自然
- LLM-as-a-judge: スコープ超過、派生 ADR 候補
- 構造化出力: streaming UX を犠牲にする

## 引き受けるトレードオフ

- **Rails 側で SSE chunk 毎に regex スキャン**: 1 chunk あたり数十文字 × 数十 chunk なので CPU は問題にならない。observability で per-chunk のスキャン時間を計測できるよう logger.tagged を入れる
- **partial buffering の複雑度**: chunk 境界をまたぐ marker のため Rails 側に未確定 tail バッファ。バグ温床になりやすい → unit-test で「marker が `[#src_` の後で chunk 終わり、次 chunk で `3]`」「不完全 marker のまま done が来る」「marker らしき文字列が code block 内にある (escape)」を網羅

> **Phase 3 と Phase 4 の境界 (実装注)**:
> Phase 3 (同期 RAG) では `RagOrchestrator#assemble_from_events` が **完成 body から事後に**
> citation を組み立てる。chunk 単位の partial buffering / regex incremental parse は **Phase 3 では不要**.
> Phase 4 (SSE proxy) では Rails が ai-worker からの chunked stream を消費しながら **chunk 単位で**
> regex で marker を抽出し、frontend へ event:chunk を流す前に検証して event:citation_invalid を
> 注入する形に書き直す。Phase 3 の assemble_from_events は **捨てる前提**で書かれており、
> Phase 4 で再利用しない (ADR 0005 の「synthesize_stream 同期消費は Phase 4 で捨てる」と整合).
- **二重 assert (ai-worker 警告 + Rails 検証)**: コード重複だが **意図的**: ai-worker の単体テストでも assert が走り、Rails の境界が ai-worker のバグを素通りさせない保険になる
- **本文に invalid marker が残る**: UX 上はキレイではないが、本文改変より監査整合性を優先 (citations テーブルが clean な方が価値が高い)
- **ai-worker のテストの責務**: ai-worker は assert を warn で出すので、テストは「warn が出ること」までに留める。assert を panic にしない判断は本 ADR で固定
- **regex の制限**: `\[#(src_\d+)\]` 固定。日本語かっこ「【】」や別記法 (`(*1)`) は対象外。LLM プロンプト側で記法を固定化することで対応 (Phase 4 の implementation note で扱う)
- **realtime feedback**: invalid marker の通知は frontend に届くが、実際の本文には残ったまま。UX として "薄字レンダ" を frontend で実装する必要 (Phase 4)

## このADRを守るテスト / 実装ポインタ（Phase 4 以降で実装）

- `perplexity/backend/app/services/citation_validator.rb` — regex 抽出 + allowed_source_ids 照合の純関数 PORO
- `perplexity/backend/app/services/sse_proxy.rb` — partial buffering と event 振り分け (ADR 0003 と共有)
- `perplexity/backend/spec/services/citation_validator_spec.rb` — 正常 / 不正 / 境界 (chunk またぎ) / unicode escape
- `perplexity/backend/spec/requests/queries_stream_citations_spec.rb` — SSE 全体としてイベント順 (chunk → citation_invalid → done) を assert
- `perplexity/ai-worker/services/synthesizer.py` — `assert source_id in allowed_source_ids; logger.warning` パターン
- `perplexity/ai-worker/tests/test_synthesizer_assert.py` — ai-worker 側の自衛 warn が出ること
- `perplexity/playwright/tests/citation_invalid.spec.ts` — invalid marker が本文に残るが薄字でハイライトされ、citation popover が出ないこと

## 関連 ADR

- ADR 0001: RAG パイプライン分割 (allowed_source_ids が retrieve 結果から組まれる前提)
- ADR 0003: SSE streaming (検証は SSE proxy 経路で行う)
- github ADR 0004: CI ステータス集約 (内部 ingress / 信頼境界の議論が並走)
