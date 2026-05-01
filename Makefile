# Service Architecture Lab — top-level task runner
#
# Usage: `make help` で全ターゲット一覧を表示する。
# 各ターゲットの説明は `## ` 以降の行から自動生成される。
#
# 命名規約: `<service>-<action>` で揃える。
#   - <service>: slack / youtube / github / perplexity / (今後追加)
#   - <action>:  deps-up / deps-down / setup / backend / backend-test /
#                frontend / frontend-lint / ai / e2e / test

SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# ─── help ─────────────────────────────────────────────────────────────────────

.PHONY: help
help: ## このヘルプを表示
	@awk 'BEGIN {FS = ":.*?## "; printf "\nUsage: make \033[36m<target>\033[0m\n\nTargets:\n"} \
		/^# ─── / {sub(/^# ─── /, ""); sub(/ ─.*/, ""); printf "\n\033[1m%s\033[0m\n", $$0; next} \
		/^[a-zA-Z0-9_-]+:.*?## / {printf "  \033[36m%-28s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# ─── common ───────────────────────────────────────────────────────────────────

.PHONY: openapi-lint
openapi-lint: ## OpenAPI スキーマを Redocly CLI で lint (slack / youtube)
	npx -y @redocly/cli@latest lint --config redocly.yaml

.PHONY: ci-local
ci-local: openapi-lint slack-test youtube-test github-test perplexity-test ## CI 相当のチェックをローカルで一通り実行

# ─── slack ────────────────────────────────────────────────────────────────────

.PHONY: slack-deps-up
slack-deps-up: ## slack 依存コンテナ (mysql:3307 / redis:6379) を起動
	cd slack && docker compose up -d mysql redis

.PHONY: slack-deps-down
slack-deps-down: ## slack 依存コンテナを停止
	cd slack && docker compose down

.PHONY: slack-setup
slack-setup: slack-deps-up ## slack 全コンポーネントの初期セットアップ
	cd slack/backend   && bundle install && bundle exec rails db:prepare
	cd slack/frontend  && npm install
	cd slack/ai-worker && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
	cd slack/playwright && npm install

.PHONY: slack-backend
slack-backend: ## slack backend (Rails API) を :3010 で起動
	cd slack/backend && bundle exec rails server -p 3010

.PHONY: slack-backend-test
slack-backend-test: ## slack backend テスト (minitest)
	cd slack/backend && bundle exec rails test

.PHONY: slack-frontend
slack-frontend: ## slack frontend (Next.js) を :3005 で起動
	cd slack/frontend && npm run dev

.PHONY: slack-frontend-lint
slack-frontend-lint: ## slack frontend の lint + typecheck
	cd slack/frontend && npm run lint && npx tsc --noEmit

.PHONY: slack-ai
slack-ai: ## slack ai-worker (FastAPI) を :8000 で起動
	cd slack/ai-worker && uvicorn main:app --port 8000

.PHONY: slack-e2e
slack-e2e: ## slack Playwright E2E (要: backend / frontend / ai-worker 起動済み)
	cd slack/playwright && AI_WORKER_RUNNING=1 npm test

.PHONY: slack-test
slack-test: slack-backend-test slack-frontend-lint ## slack の backend テスト + frontend lint を一括実行

# ─── youtube ──────────────────────────────────────────────────────────────────

.PHONY: youtube-deps-up
youtube-deps-up: ## youtube 依存コンテナ (mysql:3308) を起動
	cd youtube && docker compose up -d mysql

.PHONY: youtube-deps-down
youtube-deps-down: ## youtube 依存コンテナを停止
	cd youtube && docker compose down

.PHONY: youtube-setup
youtube-setup: youtube-deps-up ## youtube 全コンポーネントの初期セットアップ
	cd youtube/backend   && bundle install && bundle exec rails db:prepare
	cd youtube/frontend  && npm install
	cd youtube/ai-worker && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
	cd youtube/playwright && npm install

.PHONY: youtube-backend
youtube-backend: ## youtube backend (Rails API) を :3020 で起動
	cd youtube/backend && bundle exec rails server -p 3020

.PHONY: youtube-jobs
youtube-jobs: ## youtube Solid Queue ワーカーを起動
	cd youtube/backend && bundle exec bin/jobs

.PHONY: youtube-backend-test
youtube-backend-test: ## youtube backend テスト (RSpec)
	cd youtube/backend && bundle exec rspec

.PHONY: youtube-frontend
youtube-frontend: ## youtube frontend (Next.js) を :3015 で起動
	cd youtube/frontend && npm run dev

.PHONY: youtube-frontend-lint
youtube-frontend-lint: ## youtube frontend の lint + typecheck
	cd youtube/frontend && npm run lint && npx tsc --noEmit

.PHONY: youtube-ai
youtube-ai: ## youtube ai-worker (FastAPI) を :8010 で起動
	cd youtube/ai-worker && uvicorn main:app --port 8010

.PHONY: youtube-e2e
youtube-e2e: ## youtube Playwright E2E (要: backend / frontend / ai-worker 起動済み)
	cd youtube/playwright && npm test

.PHONY: youtube-test
youtube-test: youtube-backend-test youtube-frontend-lint ## youtube の backend テスト + frontend lint を一括実行

# ─── github ───────────────────────────────────────────────────────────────────

.PHONY: github-deps-up
github-deps-up: ## github 依存コンテナ (mysql:3309) を起動
	cd github && docker compose up -d mysql

.PHONY: github-deps-down
github-deps-down: ## github 依存コンテナを停止
	cd github && docker compose down

.PHONY: github-setup
github-setup: github-deps-up ## github 全コンポーネントの初期セットアップ
	cd github/backend   && bundle install && bundle exec rails db:prepare
	cd github/frontend  && npm install
	cd github/ai-worker && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
	cd github/playwright && npm install

.PHONY: github-backend
github-backend: ## github backend (Rails GraphQL) を :3030 で起動
	cd github/backend && bundle exec rails server -p 3030

.PHONY: github-backend-test
github-backend-test: ## github backend テスト (RSpec)
	cd github/backend && bundle exec rspec

.PHONY: github-frontend
github-frontend: ## github frontend (Next.js) を :3025 で起動
	cd github/frontend && npm run dev

.PHONY: github-frontend-lint
github-frontend-lint: ## github frontend の lint + typecheck
	cd github/frontend && npm run lint && npx tsc --noEmit

.PHONY: github-ai
github-ai: ## github ai-worker (FastAPI) を :8020 で起動
	cd github/ai-worker && uvicorn main:app --port 8020

.PHONY: github-e2e
github-e2e: ## github Playwright E2E (要: backend / frontend 起動済み)
	cd github/playwright && npm test

.PHONY: github-test
github-test: github-backend-test github-frontend-lint ## github の backend テスト + frontend lint を一括実行

# ─── perplexity ───────────────────────────────────────────────────────────────

.PHONY: perplexity-deps-up
perplexity-deps-up: ## perplexity 依存コンテナ (mysql:3310) を起動
	cd perplexity && docker compose up -d mysql

.PHONY: perplexity-deps-down
perplexity-deps-down: ## perplexity 依存コンテナを停止
	cd perplexity && docker compose down

.PHONY: perplexity-setup
perplexity-setup: perplexity-deps-up ## perplexity 全コンポーネントの初期セットアップ
	cd perplexity/backend   && bundle install && bundle exec rails db:prepare
	cd perplexity/ai-worker && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt

.PHONY: perplexity-backend
perplexity-backend: ## perplexity backend (Rails API) を :3040 で起動
	cd perplexity/backend && bundle exec rails server -p 3040

.PHONY: perplexity-backend-test
perplexity-backend-test: ## perplexity backend テスト (RSpec)
	cd perplexity/backend && bundle exec rspec

.PHONY: perplexity-ai
perplexity-ai: ## perplexity ai-worker (FastAPI) を :8030 で起動
	cd perplexity/ai-worker && uvicorn main:app --port 8030

.PHONY: perplexity-ai-test
perplexity-ai-test: ## perplexity ai-worker テスト (pytest)
	cd perplexity/ai-worker && .venv/bin/python -m pytest tests/

.PHONY: perplexity-seed
perplexity-seed: ## perplexity の seed (5 ドキュメント / 要 ai-worker 起動)
	cd perplexity/backend && bundle exec rails db:seed

.PHONY: perplexity-test
perplexity-test: perplexity-backend-test perplexity-ai-test ## perplexity の backend + ai-worker テストを一括実行
