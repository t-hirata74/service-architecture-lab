# Service Architecture Lab

有名 SaaS のアーキテクチャをローカル環境で再現し、設計理解と技術力向上を目指す検証用プロジェクト群。

> 単なるクローンではなく「サービスが解いている技術課題を、小さく再現する」ことを目的とする。  
> 設計方針は [CLAUDE.md](CLAUDE.md)、各プロジェクトの詳細はそれぞれの `README.md` を参照。

---

## プロジェクト一覧

| プロジェクト | 元サービス | 主な技術課題 | ステータス | ドキュメント |
| --- | --- | --- | --- | --- |
| [`slack`](slack/) | Slack 風リアルタイムチャット | WebSocket fan-out / 既読 cursor 整合性 / Rails ↔ Python 境界 | 🟢 MVP 完成 (E2E 6 件通過) | [README](slack/README.md) ・ [Architecture](slack/docs/architecture.md) ・ [ADR (5)](slack/docs/adr/) |
| [`youtube`](youtube/) | YouTube 風動画プラットフォーム | 非同期動画変換パイプライン / 状態機械 / Rails ↔ Python 境界 (タグ抽出 / サムネ / レコメンド) / Solid Queue (Redis 不使用) | 🟡 Phase 4 (ai-worker 統合 / RSpec 40 件) | [README](youtube/README.md) ・ [Architecture](youtube/docs/architecture.md) ・ [ADR (3 Proposed / 2 Accepted)](youtube/docs/adr/) |
| `github` | GitHub 風 Issue Tracker | 権限グラフ / Issue・PR モデル / CI ステータス集約 | ⚪ 未着手 | — |

---

## slack プロジェクトのハイライト

- **2 BrowserContext での双方向 WebSocket fan-out** を Playwright で E2E 検証（[ADR 0001](slack/docs/adr/0001-realtime-delivery-method.md)）
- **既読 cursor の単調増加ガード** + 多デバイス同期の broadcast を minitest で検証（[ADR 0002](slack/docs/adr/0002-message-persistence-and-read-tracking.md)）
- **Slack 実構成と整合する MySQL** + Vitess 想定の言及（[ADR 0003](slack/docs/adr/0003-database-choice.md)）
- **rodauth-rails + JWT** によるクロスオリジン認証（[ADR 0004](slack/docs/adr/0004-authentication-strategy.md)）
- **Rails ↔ Python ai-worker** の責務境界（FastAPI モック要約）

技術スタック: Next.js 16 / React 19 / Tailwind v4 / Rails 8 (API) / rodauth-rails / ActionCable / Python 3.13 / FastAPI / MySQL 8 / Redis 7 / Playwright

---

## ディレクトリ構成

```text
service-architecture-lab/
  slack/                  # Slack 風 (実装済み / E2E 通過)
  youtube/                # YouTube 風 (Phase 1 雛形)
  github/                 # 予定
  docs/                   # 共通ルール（走りながら整備）
  infra/
    terraform/            # 「本番化するなら」の設計図のみ（未実行）
  CLAUDE.md               # 設計方針・スコープ・ADR 運用
  .github/workflows/      # CI (GitHub Actions)
```

---

## CI

GitHub Actions でプロジェクトごとに lint / test を並列実行する。

- **backend**: MySQL + Redis サービスを立ち上げて Rails minitest を実行
- **frontend**: ESLint + TypeScript の型チェック
- **ai-worker**: requirements を解決してインポート確認 + uvicorn boot smoke

設定は [`.github/workflows/ci.yml`](.github/workflows/ci.yml)。

---

## 起動 (slack)

詳細は [slack/README.md](slack/README.md) を参照。

```bash
cd slack
docker compose up -d mysql redis            # 3307, 6379

cd backend && bundle exec rails db:create db:migrate
bundle exec rails server -p 3010            # API on http://localhost:3010

cd ../ai-worker && source .venv/bin/activate && uvicorn main:app --port 8000
cd ../frontend  && npm run dev               # http://localhost:3005
cd ../playwright && AI_WORKER_RUNNING=1 npm test
```

---

## ライセンス

学習・ポートフォリオ目的の個人プロジェクト。
