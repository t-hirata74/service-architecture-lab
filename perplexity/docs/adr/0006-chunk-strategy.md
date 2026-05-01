# ADR 0006: チャンク分割戦略

## ステータス

Accepted（2026-05-01）

## コンテキスト

ADR 0001 で `retrieve / extract / synthesize` の 3 ステージに RAG パイプラインを分割した。retrieve の粒度 = chunk であり、ADR 0002 で「FULLTEXT は `chunks(body)` に張る」と決めた。

しかし **chunk 自体をどう作るか** (source の分割戦略) は意外と RAG 品質を支配する論点で:

- **長すぎる chunk** = 関連薄い箇所も含まれて cosine / BM25 がノイズに引きずられる、引用粒度も粗くなる
- **短すぎる chunk** = 文脈が切れて answer が壊れる、retrieve では当たるが synthesize で意味を取り違える
- **境界またぎ** = 「東京タワーは 1958 年に / 完成した」が 2 chunk に割れると、それぞれが独立に retrieve されても根拠として弱い

実 RAG では以下の戦略が混在する:

| 戦略 | 概要 | 代表的な使い所 |
| --- | --- | --- |
| 固定長 (fixed-size) | 文字数 / token 数で機械的に切る | LangChain `CharacterTextSplitter` のデフォルト |
| 固定長 + 改行優先 | 区切り候補 (改行 / 句点) を優先しつつ最大長で切る | LangChain `RecursiveCharacterTextSplitter` |
| 文境界 (sentence boundary) | NLP で文を検出し、文単位 / 文 N 個単位で切る | spaCy / GiNZA を使う日本語 RAG |
| Overlap window | 隣接 chunk と 50〜100 文字 overlap させる | 境界またぎ情報損失を軽減 |
| Hierarchical (parent-child) | 検索は小 chunk、生成入力は親 chunk (大) | LlamaIndex `SentenceWindowNodeParser` |
| Semantic chunking | 埋め込み類似度で「意味の切れ目」を検出 | LangChain `SemanticChunker` |

> 学習対象は **「chunk 戦略を変えると検索品質がどう変わるか」を体感できる土台を作ること**。
> Phase 1 で全戦略を実装するのは過剰。**初期戦略を決め、変更可能な形で残す** のが本 ADR の目的。

制約:

- ローカル完結 (NLP 系の重量級ライブラリは入れない)
- ADR 0002 の擬似 encoder (256-d) と整合する範囲で chunk 単位を選ぶ
- 学習対象は **「初期戦略 + 後段で差し替え可能なインターフェース」** を残すこと

## 決定

**「Phase 2 では『固定長 + 改行優先 (再帰的) + overlap なし、目安 512 文字』を採用。Hierarchical / Overlap / Semantic は派生 ADR で増分追加する」** とする。

### 初期戦略の詳細

```
ChunkStrategy::FixedLengthRecursive
  max_chars: 512
  separators: ["\n\n", "\n", "。", "、", " ", ""]
  overlap_chars: 0
```

アルゴリズム (LangChain の `RecursiveCharacterTextSplitter` 相当):

1. source の `body` 全体を `separators[0]` で分割
2. 各断片が `max_chars` 以下ならそのまま chunk として確定
3. 超えていたら `separators[1]` で再分割、以下繰り返し
4. 最深 (空文字 separator) でも超える場合は文字単位で機械的に切る
5. 連続する短い断片を greedy にまとめて `max_chars` に近づける

**Overlap なし** の理由: 学習対象は「境界またぎ問題が起きること」「それを後段で overlap / hierarchical で解決すること」の **比較対象**として固定長 / overlap 0 を残したい。最初から overlap 入れると改善前後の差を体感できない。

### chunk 戦略の差し替え可能性

戦略が後段で差し替え可能になるよう **インターフェース** を以下に固定:

```ruby
# perplexity/backend/app/services/chunkers/base.rb
class Chunkers::Base
  def split(source) # → Array<{ ord:, body: }>
    raise NotImplementedError
  end

  def version  # → "fixed-length-recursive-v1" など、embedding_version とは別軸
    raise NotImplementedError
  end
end
```

- **chunker_version** カラムを `chunks` に持たせる: `(source_id, ord)` の (UNIQUE) と組み合わせて、戦略変更時の再生成を `embedding_version` 系と独立に管理
- 戦略を切り替える rake task: `rake corpus:rechunk[strategy=fixed_length_overlap]`
- 戦略の比較は **同じ source / 同じクエリで chunker_version 違いを並べて取得** することで Phase 後段で実施可能

### 派生 ADR で扱う候補（Phase 2 完了後）

| 戦略 | ADR 番号 (予定) | 動機 |
| --- | --- | --- |
| Overlap window (50-100 文字) | 0007 | 境界またぎ問題の最小限解決、固定長の延長 |
| Hierarchical (parent-child) | 0008 | retrieve は小 chunk / synthesize は親 chunk という非対称、LlamaIndex 主流形 |
| Sentence boundary (GiNZA) | 0009 | 日本語特有の意味単位切り、NLP 系ライブラリ導入の議論を伴う |
| Semantic chunking | 0010 | 擬似 encoder では意味検出ができない (ADR 0002 の限界)、real encoder への切替議論と合わせる |

## 検討した選択肢

### 1. 固定長 + 改行優先 (再帰的) + overlap なし ← 採用

- 業界標準的な初期戦略 (LangChain デフォルト)
- 改行優先で日本語の段落構造をある程度保てる
- overlap なしで「境界またぎ問題が起きる」現象を学習対象として残せる
- 欠点: 文の途中で切れる可能性は残る (separators の最深で機械的切断)

### 2. 固定長 + overlap 50 文字

- 利点: 境界またぎ問題が初期から軽減
- 欠点: **overlap なしと比較しないと改善効果を体感できない**。学習プロジェクトとして「最初から overlap」より「後で overlap を入れる」方が増分価値が見える
- → 派生 ADR で扱う

### 3. Sentence boundary (spaCy / GiNZA)

- 利点: 文単位で切れるので文脈完整性が高い
- 欠点: **NLP ライブラリ (spaCy / GiNZA + ja モデル) の導入** で ai-worker の依存が膨らむ (数百 MB)
- 欠点: 学習対象が「NLP の使い方」にズレる
- → 派生 ADR で扱う (ローカル完結方針との折衝が論点になる)

### 4. Hierarchical (parent-child)

- 利点: retrieval 品質と generation 品質の両立に効く (実 RAG の strong baseline)
- 欠点: **2 種類の chunk スキーマ**を持つ必要 (`small_chunks` と `parent_chunks`)、ADR 0002 の embedding 永続化スキーマも 2 系統に
- 欠点: Phase 2 で着手するには複雑度が高い、まず flat 1 系統で動かして肌感を得てから移行する方が順当
- → 派生 ADR で扱う (Phase 後段の有力候補)

### 5. Semantic chunking

- 利点: 意味の切れ目で chunk 化、retrieval 品質が高い
- 欠点: **擬似 encoder では意味検出が機能しない** (ADR 0002 の構造的限界)。real encoder 導入と pair で議論する必要
- → 派生 ADR で扱う (real encoder 切替と合わせる)

### 6. ノー戦略 (source 全体を 1 chunk)

- 利点: 最小実装
- 欠点: **retrieve の意味が消える** (ヒットすれば全文返る = ベクタ類似度の意味が薄い)
- 欠点: synthesize の context 長を直接膨らませるので学習に不向き
- → 採用しない

## 採用理由

- **学習価値**: 初期戦略の "限界" を Phase 2-4 で体感し、派生 ADR で改善 (overlap / hierarchical / semantic) を入れる **増分学習路線**を作る
- **アーキテクチャ妥当性**: LangChain `RecursiveCharacterTextSplitter` は実 RAG の最もポピュラーな入口、教科書的な選択
- **責務分離**: chunker は Rails 側の `services/chunkers/` 配下、戦略変更は ai-worker 不要 (chunk テキストは embedding 計算前に確定)
- **将来の拡張性**: `Chunkers::Base` インターフェース + `chunker_version` カラム + `rake corpus:rechunk` で、戦略差し替えが embedding 再計算と独立に動く

## 却下理由

- 初期から overlap / hierarchical / semantic: **比較対象としての flat 固定長を持たない**まま改善版を入れると学習価値が消える
- ノー戦略: retrieval の意味が消える
- Sentence boundary を初手採用: NLP 依存追加が学習スコープを越える

## 引き受けるトレードオフ

- **境界またぎ問題が初期から起きる**: これは **学習対象として意図** している。Phase 4 で SSE デモを動かすと「重要文の前半しか chunk に入っていない」ケースを観察できる → ADR 0007 (overlap) の動機が見える順序
- **chunk_version の並走管理**: `embedding_version` (ADR 0002) と `chunker_version` (本 ADR) の 2 軸が `chunks` テーブルに乗る。**`(source_id, ord, chunker_version)` UNIQUE** とし、chunker 違いの chunk が並列で存在できる構造にする (戦略比較に必要)
- **chunker 切替時の embedding 再計算**: `chunker_version` が変わると chunk 内容も変わるので embedding 再計算が必要。`rake corpus:rechunk` は内部的に `corpus:reembed` を呼び出すフロー
- **separators の妥当性**: 日本語の `。` `、` を入れているが、英文混在 source では `.` を入れていない (`""` の最深で吸収される)。学習用途では問題なし、多言語対応は本 ADR スコープ外
- **chunker_version をテストでどう扱うか**: `Chunkers::Base#version` を hard-coded とし、戦略実装変更時に手動でインクリメント。文字列が変わると `chunks` 行が orphan 化する → `rake corpus:rechunk` で清掃する規律
- **Phase 2 では戦略比較機能は作らない**: インターフェースだけ用意。実際の比較は派生 ADR (0007 以降) で着手する増分路線

## このADRを守るテスト / 実装ポインタ（Phase 2 以降で実装）

- `perplexity/backend/db/migrate/*_create_chunks.rb` — `(source_id, ord, chunker_version)` UNIQUE
- `perplexity/backend/app/services/chunkers/base.rb` — interface
- `perplexity/backend/app/services/chunkers/fixed_length_recursive.rb` — Phase 2 採用
- `perplexity/backend/app/services/corpus_ingestor.rb` — chunker と embedder を順に呼ぶ orchestrator (ADR 0001 の「embedding 書き込みは Rails 経由」と整合)
- `perplexity/backend/lib/tasks/corpus.rake` — `corpus:ingest` / `corpus:rechunk` / `corpus:reembed`
- `perplexity/backend/spec/services/chunkers/fixed_length_recursive_spec.rb` — separator 優先順序 / max_chars 境界 / 連続短断片の greedy 結合 / 単一文字超過時の機械切断
- `perplexity/backend/spec/services/corpus_ingestor_spec.rb` — chunker_version + embedding_version の二軸更新

## 関連 ADR

- ADR 0001: RAG パイプライン分割 (chunker は Rails 側)
- ADR 0002: hybrid retrieval (chunk 単位の embedding と FULLTEXT)
- ADR 0007 (予定): Overlap window
- ADR 0008 (予定): Hierarchical (parent-child) chunking
