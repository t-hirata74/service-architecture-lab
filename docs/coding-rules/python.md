# Python (ai-worker) コーディング規約

`slack/ai-worker/` で実際に採用している規約を共通ルールとしてまとめる。

ai-worker の役割は **AI 処理 / レコメンド / 検索ランキング / 非同期ワーカーのモック実装**。  
本物の LLM 呼び出しや外部 API は使わない（CLAUDE.md「外部 API 禁止」方針）。

---

## 技術スタック

- Python 3.13
- FastAPI + uvicorn
- pydantic v2（リクエスト / レスポンスのモデル定義）
- `requirements.txt` で固定バージョン管理（lock ファイル相当）

依存は最小に保つ。**numpy / pandas / sklearn 等は実際に必要になるまで入れない**。

---

## ディレクトリ構成

```text
ai-worker/
  main.py            # FastAPI app + endpoint
  requirements.txt
  README.md
```

機能が増えたら以下のように分割する:

```text
  app/
    __init__.py
    api.py           # FastAPI ルーティング
    schemas.py       # pydantic models
    services/        # 個別ロジック (要約 / 推薦 / etc.)
```

最初から分割しない。`main.py` が 200 行を超えたタイミングで切り出す。

---

## エンドポイント設計

- `GET /health` を必ず生やす（CI のスモークで叩く）
- 入力 / 出力は pydantic モデルで型付け
- パスは `/<verb>`（例: `/summarize`, `/recommend`）。RESTful ではなく **動詞ベース** にする（バッチ処理 / 単発計算が中心のため）

---

## pydantic モデル

- リクエスト / レスポンスは別クラスにする（`SummarizeRequest` / `SummarizeResponse`）
- バリデーションは `Field` の `min_length` / `max_length` / `default_factory` を使う
- 「あり得ない」入力に対する手書きの assert は書かない。pydantic が落とす

---

## モック実装の方針

- 決定論的（同じ入力で同じ出力）にする。テストで再現できるように
- ランダム / 時刻依存 / I/O は避ける
- 結果には `(mock)` を入れるなど、本物でないことが明示的に分かる文字列を返す

---

## Rails からの呼び出し

- Rails 側 `AiWorkerClient` (`slack/backend/app/services/ai_worker_client.rb`) から HTTP で呼ばれる
- ベース URL は環境変数 `AI_WORKER_URL`（slack: デフォルト `http://localhost:8000` / youtube: デフォルト `http://localhost:8010`）
- Rails 側で open 2s / read 10s タイムアウトを設定済み。Python 側も**重い処理を作らない**

### graceful degradation を前提に書く

ai-worker は **本流ではない** 補助レイヤー。Rails 側は失敗時に `200 + degraded: true`
で返す（[`operating-patterns.md`](../operating-patterns.md#graceful-degradation)）。
そのため Python 側で:

- 例外を返すよりも **空配列 / 既定値で 200 を返す** ほうが望ましい
- どうしても異常系を返す場合は **5xx ではなく 4xx**（例: バリデーションエラーは 422）
- ヘルスチェック `/health` は **依存先（DB / モデルロード）に左右されず** 200 を返す
- ジョブ完了通知 / コールバックを Rails に投げる方向の通信はしない（pull のみ）

### バイナリレスポンス

サムネ画像のような binary は `Response(content=bytes, media_type="image/png")` で返す。
JSON を期待する Rails 側のクライアントが切り替えられるよう、エンドポイントを分ける。

---

## Lint / Format

- 当面 `ruff` などは導入していない。FastAPI / pydantic の型でコンパイル相当の検査は得られている前提
- 規模が大きくなったら `ruff` + `ruff format` を入れる方針（その時点で ADR を立てる）

---

## テスト

- 現時点ではテストコードを書いていない（モック実装のため）
- ロジックが増え始めたタイミングで `pytest` を導入する。導入時は CI に組み込む

---

## CI で検証していること（最小）

`.github/workflows/ci.yml` の `slack-ai-worker` ジョブ:

1. `pip install -r requirements.txt` で依存解決
2. `python -c "import main"` で import が通ることを確認
3. `uvicorn main:app` を起動 → `/health` を叩いて 200 を確認

ロジックが増えたら `pytest` ジョブを追加する。

---

## やらないこと

- 本物の LLM / 外部 API 呼び出し
- 大きな ML 依存の導入（先回り禁止）
- 非同期化（async / await）を学習目的なしで入れる
