# github / ai-worker

GitHub 風プロジェクトの AI 処理（モック）レイヤ。

- `POST /review` — PR の AI レビュー（モック）
- `POST /code-summary` — Issue / PR 説明の要約
- `POST /check/run` — モック CI チェックを動かして backend `/internal/commit_checks` に upsert を投げる

実 LLM / 実 git は扱わない（リポジトリ全体のローカル完結方針）。

## 起動

```bash
cd github/ai-worker
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --port 8020
```

## 環境変数

- `BACKEND_URL` (default `http://localhost:3030`)
- `INTERNAL_INGRESS_TOKEN` (default `dev-internal-token`、backend の `X-Internal-Token` と一致させる)

## 動作確認

```bash
curl -sS http://localhost:8020/health

curl -sS -H "Content-Type: application/json" -X POST http://localhost:8020/check/run \
  -d '{"owner":"acme","name":"tools","head_sha":"abc123","check_name":"build"}'
```
