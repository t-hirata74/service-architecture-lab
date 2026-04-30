# ai-worker

YouTube 風プロジェクトの AI 処理（モック）レイヤ。

## 役割

- **レコメンド** — タグの重複度 (Jaccard) ベースの関連動画スコアリング
- **タグ抽出** — タイトル/説明から頻度ベースの簡易タグ抽出
- **サムネ生成** — Pillow で固定レイアウトのプレースホルダ画像生成

実コーデック処理 / 実 ML モデルは使わず、Rails ↔ Python の責務分離と境界設計の練習を主目的にする。

## 起動

```bash
cd ai-worker
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8010
```

## エンドポイント

| Method | Path             | 説明                                          |
| ------ | ---------------- | --------------------------------------------- |
| GET    | /health          | ヘルスチェック                                |
| POST   | /recommend       | 類似動画レコメンド（Jaccard モック）          |
| POST   | /tags/extract    | タイトル/説明からタグ抽出                     |
| POST   | /thumbnail       | サムネ PNG を生成して返す                     |

### /recommend リクエスト例

```json
{
  "target":     { "id": 1, "title": "Rails入門", "tags": ["rails", "ruby"] },
  "candidates": [
    { "id": 2, "title": "Active Record",  "tags": ["rails", "db"] },
    { "id": 3, "title": "Pythonで機械学習", "tags": ["python", "ml"] }
  ],
  "limit": 5
}
```
