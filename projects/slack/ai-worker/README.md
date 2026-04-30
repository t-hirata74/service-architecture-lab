# ai-worker

Slack 風プロジェクトの AI 処理（モック）レイヤ。

## 役割

- メッセージ要約のモック実装
- 将来的にメッセージ分析や検索ランキング等を担当する想定

## 起動

```bash
cd ai-worker
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

## エンドポイント

| Method | Path        | 説明                           |
| ------ | ----------- | ------------------------------ |
| GET    | /health     | ヘルスチェック                 |
| POST   | /summarize  | チャンネルメッセージの要約生成 |

### /summarize リクエスト例

```json
{
  "channel_name": "general",
  "messages": [
    { "id": 1, "user": "Alice", "body": "新機能のデザイン共有しました" },
    { "id": 2, "user": "Bob",   "body": "確認します！" }
  ]
}
```

### レスポンス例

```json
{
  "channel_name": "general",
  "message_count": 2,
  "participants": ["Alice", "Bob"],
  "summary": "#general には 2 件のメッセージ。主な発言者: Alice (1件), Bob (1件)。話題は「新機能のデザイン共有しました」から始まり「確認します！」で終わっています。"
}
```
