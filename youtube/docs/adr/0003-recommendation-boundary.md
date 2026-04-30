# ADR 0003: レコメンド機能の責務分離（Rails ↔ ai-worker）

## ステータス

Accepted（2026-05-01）

## コンテキスト

YouTube の特徴的な機能のひとつが「関連動画レコメンド」。
本プロジェクトではモック実装（タグの Jaccard 類似度ベース）に留めるが、
**「Rails 側でやるか / Python の ai-worker に切り出すか」** の境界設計が学習対象になる。

Slack で同じ判断（メッセージ要約）をしたとき ai-worker 側に切り出した経緯があるが、
レコメンドは要約と違って **大量の候補を計算する** 性質があり、判断材料が異なる。

制約：

- ローカル完結（実 ML モデル不可）
- Rails と Python の責務境界をコードから読み取れる構造にしたい
- 将来的にレコメンドアルゴリズムを差し替える可能性がある

## 決定

**レコメンドの計算は ai-worker に切り出し、Rails は永続化・候補選定・境界制御を担当する** を採用する。

- Rails: 対象動画 + 候補集合（同一カテゴリ等）を選び、`POST /recommend` で ai-worker に渡す
- ai-worker: スコアリングして上位 N を返す（Phase 1 では Jaccard モック / Phase 4 で実装）
- レスポンスのキャッシュは Rails 側 (Solid Cache) で持つ

## 検討した選択肢

### 1. ai-worker に切り出す ← 採用

- 利点: Slack の要約と同じ責務境界パターン → リポジトリ全体で一貫した設計言語
- 利点: 将来 numpy / scikit-learn / 行列分解等のアルゴリズムに置き換えやすい
- 利点: 重い計算が Rails の Puma スレッドを占有しない
- 欠点: ネットワーク越境のレイテンシとタイムアウト設計が必要

### 2. Rails 内で計算

- 利点: ネットワーク越境なし、デプロイ単純
- 利点: モックレベルの計算なら Ruby で十分
- 欠点: Slack で確立した境界パターンを破る → リポジトリ全体での学習価値が落ちる
- 欠点: 将来本物の ML を載せるとき結局 Python 側に剥がす必要がある

### 3. Rails で計算しつつインタフェースは抽象化（Strategy パターン）

- 利点: 後で差し替えやすい
- 欠点: ローカルで動く現物がないと学習材料にならない

## 採用理由

- **学習価値**: Slack の要約と同じ判断軸を別ドメインで再適用できることを示せる（"判断の再現性"）
- **アーキテクチャ妥当性**: 実プロダクトでもレコメンドは別サービス化される定石
- **責務分離**: 永続化（Rails） / 計算（Python） / 配信（Next.js）の三層が綺麗に分かれる
- **将来の拡張性**: ai-worker 側のアルゴリズムだけ差し替えれば Rails には影響しない

## 却下理由

- Rails 内計算: リポジトリ内のスタック多様性と境界パターンの一貫性が失われる
- Strategy パターン抽象化のみ: 動く現物がないと学習にならない

## 引き受けるトレードオフ

- **ネットワーク越境**: タイムアウト / リトライ / サーキットブレーカが必要（最小実装で許容）
- **スキーマ整合**: Rails と FastAPI でレコメンド I/F を二重に定義することになる（Pydantic + Ruby Hash）
- **キャッシュ整合性**: 候補集合が変わったらキャッシュを破棄する責任が Rails 側に発生

## このADRを守るテスト / 実装ポインタ

- `youtube/backend/app/services/ai_worker_client.rb` — Net::HTTP / open=2s, read=10s / 失敗時 `AiWorkerClient::Error` を返し本流は止めない
- `youtube/ai-worker/main.py:recommend` — Jaccard モックの実装
- `youtube/backend/spec/services/ai_worker_client_spec.rb` — 200 / 5xx / 接続不能のスタブ検証
- `youtube/backend/spec/jobs/extract_tags_job_spec.rb` — タグマージ + 失敗時 noop
- `youtube/backend/spec/jobs/generate_thumbnail_job_spec.rb` — Active Storage 添付 + degrade
- `youtube/backend/app/controllers/videos_controller.rb#recommendations` — `degraded: true` フォールバック

## 関連 ADR

- ADR 0001: アップロード状態機械
- ADR 0002: ストレージ設計
- Slack ADR 0001（参照）: ai-worker 切り出しの先行判断
