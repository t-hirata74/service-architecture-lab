# ADR 0002: 権限グラフのモデリング

## ステータス

Accepted（2026-05-01）

## コンテキスト

GitHub の権限は **Org → Team → Repository → Issue/PR** という階層で継承され、ユーザは複数の Team に所属できる。
本プロジェクトは「権限グラフ」を中核技術課題として再現する：

- Org member の base role (admin / member / outside_collaborator)
- Team による Repo への role 付与 (read / triage / write / maintain / admin)
- 個人 Collaborator (Repo 直付け) による役割付与
- **「あるユーザは、あるリソースに対して、ある操作ができるか？」** を解決層から問えること

制約：

- ローカル完結（IAM / OPA / Cedar 等の外部認可サービスは使わない）
- GraphQL の field 単位認可と相性が良い設計が望ましい (ADR 0001)
- ローカル MySQL のみで完結（ReBAC ライブラリの導入は学習目的に対して過剰）

## 決定

**「ロール表 + 解決ヘルパー (`PermissionResolver`) + Pundit policy の 3 層構成」** を採用する。

- **ロール永続化**:
  - `memberships(org_id, user_id, role)` — Org の base role
  - `team_members(team_id, user_id, role)` — Team の role (admin / maintainer / member)
  - `team_repository_roles(team_id, repository_id, role)` — Team が Repo に対して持つ role
  - `repository_collaborators(repository_id, user_id, role)` — 個人 Collaborator
- **解決ヘルパー**: `PermissionResolver.new(user, repository).effective_role` が **「Org base / Team 経由 / 個人付与の最大権限」を計算**して返す
- **Policy 層**: Pundit を **GraphQL resolver / field 内で呼ぶ**。`policy.can_assign?` のような action 単位メソッドが effective_role を見て判定
- **Issue / PR の write は repository.role 派生**：Issue 個別に collaborator を付ける機能は (実 GitHub にあるが) スコープ外

## 検討した選択肢

### 1. ロール表 + Resolver (採用)

- 表の数は 4 つで済み、SQL で素直に追える
- Resolver が「最大権限」を一箇所で計算するので Policy が薄く保てる
- 利点: GraphQL field 認可で `policy.can?(:assign_reviewers, pr)` を呼ぶだけ

### 2. Permission ビット表（権限フラグを直接 user × repo に展開）

- 実装は単純だが、メンバー追加 / Team 編集のたびに展開更新が必要
- 利点: クエリは一発
- 欠点: **継承の概念が DB に表現されない**ので、ADR が掲げる「権限グラフを学ぶ」目的に対して薄い

### 3. ReBAC（SpiceDB / OpenFGA 相当を自前で）

- 学術的には正しい
- 欠点: ローカル完結方針に対して重すぎる。学習対象が「外部認可サービスの操作」になり、Rails 内の責務分離からズレる

## 採用理由

- **学習価値**: 「Org / Team / Repo / 個人」という階層が DB スキーマに表れる。Resolver が継承を解く実装を書ける
- **アーキテクチャ妥当性**: 実 GitHub も似た方向（base role × team × collaborator）。極端な ReBAC ではない
- **責務分離**: 永続化（テーブル）/ 解決（Resolver）/ 適用（Policy / GraphQL）の 3 層が分かれている
- **GraphQL field 認可との相性**: resolver で `policy.allow?` を呼ぶだけで field を出し分けられる

## 却下理由

- 権限フラグ展開: 継承を学ぶ目的に合わない
- ReBAC: ローカル完結方針と学習スコープを越える

## 引き受けるトレードオフ

- **計算コスト**: effective_role の解決が page 単位で N 回走り得る。`graphql-batch` で repository ごとにまとめる方針 (ADR 0001 と整合)
- **キャッシュなし**: Redis を使わない。memoize は request 単位の `RequestStore` 程度に留める
- **継承の上書き**: 「Team が write 付与しているが個人が read に下げる」のような上書きは扱わない。常に **最大権限** を取る単純化
- **Issue / PR 個別ロール**: 実 GitHub の細かい個別 Collaborator 設定は除外

## このADRを守るテスト / 実装ポインタ（Phase 2 以降）

- `github/backend/app/services/permission_resolver.rb` — 継承解決の単一エントリポイント
- `github/backend/app/policies/repository_policy.rb` — Pundit policy
- `github/backend/spec/services/permission_resolver_spec.rb` — Org base + Team + Collaborator の組み合わせ
- `github/backend/spec/graphql/field_authorization_spec.rb` — 権限不足時に field が `null` で返ること

## 関連 ADR

- ADR 0001: GraphQL 採用（field 認可の前提）
- ADR 0003: Issue / PR / Review データモデル（権限が掛かる対象）
