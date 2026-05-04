# ADR 0001: コメントツリーの DB 設計 (Adjacency List + Materialized Path)

## ステータス

Accepted（2026-05-04）

## コンテキスト

`reddit` プロジェクトの中核技術課題は **「深くネストするコメントツリーを、効率良く読み出し / 投稿できる形で永続化する」** こと。Reddit のコメントは:

- 1 投稿あたり数千 〜 数万件規模になりうる
- 任意の深さに reply できる (実運用では 10 段以上もある)
- read pattern は **「ある post の全コメントをツリー順 (depth-first / score 順) で取り出す」** が支配的
- write pattern は **「あるコメントの子として 1 件追加する」** がほぼすべて (move / re-parent はしない)

ローカル完結 (MySQL 8 + FastAPI + SQLAlchemy async) の制約下で、よく知られた 4 方式を比較する:

1. **Adjacency List** — `comments.parent_id` のみ。シンプル。深さに応じて再帰 SELECT
2. **Materialized Path** — `path VARCHAR (例: "1.4.12")` を持ち、prefix 一致でサブツリーを取る
3. **Nested Set (Modified Preorder)** — `lft / rgt` を持ち、範囲問い合わせでサブツリーを取る
4. **Closure Table** — 別テーブル `comment_paths(ancestor_id, descendant_id, depth)` で全祖先関係を保持

制約:

- **MySQL 8 は recursive CTE をサポート**するため、Adjacency List 単体でも `WITH RECURSIVE` で全ツリーを取得できる
- が、recursive CTE は **per-comment lookup でインデックスが効きにくい / 1 ツリー全件取り出しに時間がかかる**ことが知られている
- 「コメントツリーの DB 設計を体感する」が学習対象なので、**1 方式に寄り切らず Adjacency List + Materialized Path のハイブリッド**を採用するほうが、各方式のトレードオフをコードに残せる

## 決定

**「Adjacency List (`parent_id`) + Materialized Path (`path`) の併用」** を採用する。

- `comments` テーブル:
  - `id BIGINT PK AUTO_INCREMENT`
  - `post_id BIGINT NOT NULL` (FK)
  - `parent_id BIGINT NULL` (self-FK、トップレベルは NULL)
  - `path VARCHAR(255) NOT NULL` (例: `"00000001/00000004/00000012"` のように **id を 0 埋めして `/` 区切り**)
  - `depth INT NOT NULL` (path の `/` 数 + 1)
  - `body TEXT NOT NULL`
  - `score INT NOT NULL DEFAULT 0` (denormalized、ADR 0002)
  - `deleted_at DATETIME NULL` (soft delete)
  - `created_at DATETIME NOT NULL`
  - INDEX `(post_id, path)` で post 内のツリー走査
  - INDEX `(post_id, score DESC)` で score 順の上位コメント取得
- **書き込み時**: `parent_id` から親の `path` を取得し、自分の `id` を末尾に append。**自分の id を path に入れたいので、INSERT は 2 段**:
  1. `INSERT INTO comments (..., path = '', depth = 0)` → 自動採番 id を取得
  2. `UPDATE comments SET path = ?, depth = ? WHERE id = ?` (親 path + 自 id)
  - 同一トランザクション内で実行し、`path` が一時的に空のレコードが他者から見えないようにする
- **読み出し**:
  - 「post 全コメントをツリー順」: `SELECT * FROM comments WHERE post_id = ? ORDER BY path` (path の lexicographic 順 = preorder)
  - 「あるコメントのサブツリー」: `WHERE post_id = ? AND path LIKE 'prefix/%'` (prefix 一致)
  - 「上位 N コメント (score 順)」: `WHERE post_id = ? AND parent_id IS NULL ORDER BY score DESC LIMIT N` → トップレベルだけは score 順、その配下はクライアント側で再帰展開
- **削除**: soft delete (`deleted_at`)。子コメントが残るので **「[deleted]」プレースホルダ表示**で UI に出す (Reddit と同じ運用)

## 検討した選択肢

### 1. Adjacency List 単体 (`parent_id` のみ)

- 利点: 最もシンプル、INSERT が 1 SQL で済む
- 利点: MySQL 8 の `WITH RECURSIVE` で全件取得は可能
- 欠点: 深いツリーで再帰 CTE のコストが線形に伸びる
- 欠点: 「あるコメントのサブツリーだけ」を効率的に取り出す手段がない (depth が分からない)

### 2. Materialized Path 単体

- 利点: 単一の `WHERE path LIKE 'prefix/%' ORDER BY path` でサブツリー取得 + 順序が同時に得られる
- 欠点: `parent_id` がないため「直接の親」を取り出すのが冗長 (`path` の最後の `/` 以降を切り出す)
- 欠点: ツリーの move (re-parent) が高コスト (子孫全件 UPDATE) → ただし Reddit はツリー move を許可しないので問題なし
- 欠点: `path` の長さ上限が深さ上限になる (`VARCHAR(255)` で 8 桁 id × `/` 区切り = 約 28 段、現実的には十分)

### 3. Nested Set (lft / rgt)

- 利点: サブツリー取得が `WHERE lft BETWEEN ? AND ?` で高速
- 欠点: **INSERT のたびに「右側の全ノード」の lft/rgt を更新**する必要がある。Reddit のような「リアルタイムに大量 reply が飛んでくる」UC では write 衝突が壊滅的
- 欠点: 学習対象としてはアカデミックだが、Reddit の特性 (大量の同時 INSERT) と決定的にミスマッチ

### 4. Closure Table

- 利点: ancestor / descendant の **全ペア**を別テーブルで持つので、任意の祖先関係クエリが 1 SQL で完結
- 欠点: INSERT のたびに **N 行** (祖先数分) の closure 行を追加する必要があり、深いツリーで write amplification
- 欠点: テーブル設計が 2 つに分かれ、整合性管理 (cascade delete) が複雑化
- 欠点: MVP の学習論点 (write/read のバランス) が見えにくい

### 5. Adjacency List + Materialized Path の併用 ← 採用

- 利点: **`parent_id` で「直接の親」、`path` で「ツリー走査」** と用途を分離できる
- 利点: INSERT は **2 段だが軽量** (採番 → path 計算 UPDATE)。Nested Set のような全ノード更新は不要
- 利点: 学習対象として **「インデックス設計を 2 つの軸 (post_id+path / post_id+score) で共存させる」** という現実的なテーマに踏み込める
- 欠点: `path` 計算ロジックを 1 箇所に閉じ込める必要がある (`comments.repository.create_with_path`)

## 採用理由

- **学習価値**: 「Adjacency List だけ / Closure Table だけ」では見えない **「インデックス設計の二系統」** という Reddit ライクな設計判断をコードに残せる
- **Reddit のドメイン特性に整合**: ツリー move を許可しない / 大量 INSERT が走る / read は preorder traversal が支配的 という条件で `path` 方式が最も筋が良い
- **MySQL 8 単体で完結**: 外部依存 (Postgres LTREE / 専用 KVS) を持ち込まずに済む
- **派生 ADR の入口**: Phase 後半で「Closure Table を別途持って祖先 join を高速化する」「path を BLOB 圧縮する」を派生 ADR で扱える

## 却下理由

- **Adjacency List 単体**: サブツリー抽出に再帰 CTE が必要で、read 時のコストが線形に膨らむ
- **Nested Set**: INSERT 時の右側全更新が Reddit 的トラフィックに致命的
- **Closure Table**: write amplification が path 方式より重く、論点が「ancestor 関係の正規化」に寄りすぎる

## 引き受けるトレードオフ

- **path 採番の 2 段 INSERT**: 同一トランザクション内で `INSERT → UPDATE` が必要。`repository.create_comment` で隠蔽し、handler からは 1 関数として見せる
- **path 長による深さ上限**: `VARCHAR(255)` で約 28 段。Reddit の極端なネスト (100 段超) は **「26 段以降はスレッドを折り畳んで継続リンクを出す」** という UI 制約で吸収 (本物の Reddit と同じ運用)
- **`path` の lexicographic 順 = preorder**: 0 埋め必須。`bigint` の最大値が 19 桁なので保守的に **10 桁 0 埋め**で `path` を作る (`%010d/%010d`)
- **soft delete**: `deleted_at` を立てるだけで子は残す。UI 側で「[deleted]」プレースホルダ表示。物理削除は別 ADR で扱う
- **score order の階層整合**: 親が score 順でも子は score 順にしない (UI で「Best」ソート時のみ親をスコア順、子は path 順)。学習論点としては「**ソートの軸を depth ごとに変える**」を経験する

## このADRを守るテスト / 実装ポインタ（Phase 2 以降で実装）

- `reddit/backend/app/domain/comments/repository.py` — `create_comment(post_id, parent_id, body)` で path を採番
- `reddit/backend/app/domain/comments/repository.py` — `list_tree(post_id, root_path=None, sort="path"|"score")`
- `reddit/backend/migrations/0002_create_comments.py` — `comments (post_id, path, depth, parent_id, score, deleted_at, ...)` + index 2 本
- `reddit/backend/tests/comments/test_path.py` — 親子 path の prefix 関係 / 深さ計算 / lexicographic 順 = preorder
- `reddit/backend/tests/comments/test_tree_query.py` — `WHERE path LIKE 'prefix/%'` でサブツリーが正しく取れる
- `reddit/backend/tests/comments/test_soft_delete.py` — `deleted_at` 立て後も子コメントが取得できる

## 関連 ADR

- ADR 0002: 投票 (vote) の整合性と score の denormalize (この ADR の `score` カラムの責務)
- ADR 0003: Hot ランキングアルゴリズム (`score` を入力にした post 順位計算)
- ADR 0004: 認証方式 (comment 投稿の認可)
- ADR 0005 (派生予定): Closure Table を別途持って ancestor join を高速化
- ADR 0006 (派生予定): 26 段超の深いスレッドを「continue link」で折り畳む UI 仕様
