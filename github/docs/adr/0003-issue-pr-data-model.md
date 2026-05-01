# ADR 0003: Issue / Pull Request / Review のデータモデル

## ステータス

Accepted（2026-05-01）

## コンテキスト

GitHub の Issue と PR は「番号空間が共有される (`#123`)」「コメント・ラベル・assignee・milestone を共有する」一方、
PR だけが head/base ref / merge 状態 / review / commit status を持つ。**「共通部分は同じ、差分は明確に分離する」** 設計が要る。

スコープ：

- Issue: タイトル / 本文 / 状態 (`open`/`closed`) / labels / assignees / comments
- PR: 上記 + head/base branch / mergeable 状態 / reviews / requested_reviewers / commit_status_aggregate
- Review: PR に紐づく `approved` / `changes_requested` / `commented` の状態 + body
- Comment: Issue にも PR にも付く（PR の inline review comment は **スコープ外**、issue/pr ボディに紐づく conversation comment のみ）

制約：

- ローカル完結（実 git は扱わない）。head/base ref は文字列として持つだけ
- リポジトリ内で一意な番号 (`#1`, `#2`, ...) を Issue / PR で **共有**したい

## 決定

**「Issue / PullRequest を別テーブルに分け、`repository_issue_numbers` で番号空間を共有する」** を採用する。

- `issues(id, repository_id, number, title, body, state, author_id, ...)`
- `pull_requests(id, repository_id, number, title, body, state, head_ref, base_ref, mergeable_state, ...)`
- `repository_issue_numbers(repository_id, last_number)` — Issue / PR 採番時に **`UPDATE ... SET last_number = last_number + 1` を行 lock で取り、共通の連番を発番**
- `comments(id, commentable_type, commentable_id, author_id, body)` — Issue / PR を polymorphic で参照
- `reviews(id, pull_request_id, reviewer_id, state, body)` — `approved | changes_requested | commented`
- `labels(id, repository_id, name, color)` + `issue_labels` / `pull_request_labels` (両テーブルに別々の中間表)
- `requested_reviewers(pull_request_id, user_id)` — リクエスト中だが未レビューの状態
- 共通検索は GraphQL の `union IssueOrPullRequest` でクライアントに見せる

## 検討した選択肢

### 1. 別テーブル + 番号採番テーブル ← 採用

- スキーマが「Issue にしかない」「PR にしかない」を素直に表現できる
- 採番は `repository_issue_numbers` で `FOR UPDATE` するだけで一意性が保たれる
- 利点: GraphQL の Type も別になり、フィールドの過不足が出ない

### 2. Single Table Inheritance（`issues` テーブルに `type: 'Issue' | 'PullRequest'`）

- 番号空間が自然に共有される
- 欠点: PR にしかないカラム (head_ref / base_ref / mergeable_state) が **Issue 行で常に NULL になる**
- 欠点: GraphQL Type も polymorphic にせざるを得ず、認可・dataloader が煩雑

### 3. Polymorphic 共有 (`work_items` 親テーブル + `issues` / `pull_requests` 子テーブル)

- 関係を完全に正規化できる
- 欠点: ほぼすべての query で JOIN が増えて学習コストが上がる
- 欠点: 「番号空間共有」だけのために 3 テーブル構造は重い

## 採用理由

- **学習価値**: 番号採番の競合制御 (`FOR UPDATE`) を明示的に書く機会がある
- **アーキテクチャ妥当性**: 実 GitHub も Issue と PR を別管理しつつ番号空間だけ共有する設計
- **責務分離**: Issue / PR の状態機械をそれぞれ独立して書ける
- **GraphQL との整合**: Type を別にできるので field 認可が型ごとに閉じる

## 却下理由

- STI: NULL カラム洪水とフィールド過剰が学習対象として価値が低い
- 親子分割: 過剰正規化。番号空間共有のためだけに JOIN を増やすメリットが薄い

## 引き受けるトレードオフ

- **横断検索**: 「Issue + PR を新着順」のクエリは UNION ALL になる。pagination が複雑化するため、最初は **Issue / PR 別タブ**で出す
- **採番 hotspot**: `repository_issue_numbers` の行 lock がボトルネック化する可能性 (学習用途では非問題)
- **inline review comment**: 行番号付きコメントは扱わない。`reviews.body` のみ
- **draft PR / merge queue**: スコープ外。`mergeable_state` は `mergeable | conflict | merged | closed` の 4 値のみ

## このADRを守るテスト / 実装ポインタ（Phase 2 以降）

- `github/backend/db/migrate/*_create_issues.rb`
- `github/backend/db/migrate/*_create_pull_requests.rb`
- `github/backend/db/migrate/*_create_repository_issue_numbers.rb`
- `github/backend/app/services/issue_number_allocator.rb` — `with_lock` で連番採番
- `github/backend/spec/services/issue_number_allocator_spec.rb` — 並行採番で重複しないこと

## 関連 ADR

- ADR 0001: GraphQL 採用
- ADR 0002: 権限グラフ
- ADR 0004: CI ステータス集約（PR に集約する）
