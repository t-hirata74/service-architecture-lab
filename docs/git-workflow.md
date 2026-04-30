# Git ワークフロー

個人 / 学習リポジトリだが、ポートフォリオとして他者が読むことを想定して履歴を整える。

---

## ブランチ戦略

- デフォルトブランチは `main`
- 機能 / 修正は `feature/<topic>` / `fix/<topic>` / `chore/<topic>` 等の短命ブランチで作業し、PR を経て `main` にマージ
- 直 push を厳禁にはしないが、**PR で履歴を残せるならそうする**（後から「なぜこの変更を入れたか」を辿るため）
- マージ方式は **squash merge** 推奨（PR 単位で 1 commit 化、履歴を読みやすく）

---

## コミットメッセージ

[Conventional Commits](https://www.conventionalcommits.org/) ベース。本文は日本語で OK。

```text
<type>(<scope>): <概要>

<本文（必要なら）>
```

### type

| type | 用途 |
| --- | --- |
| `feat` | 新機能 |
| `fix` | バグ修正 |
| `docs` | ドキュメントのみ |
| `test` | テストのみ追加・修正 |
| `refactor` | 挙動を変えないリファクタ |
| `chore` | 雑務（依存更新、ディレクトリ整理 etc.） |
| `ci` | CI / GitHub Actions 関連 |

### scope

プロジェクト名 + 必要に応じてレイヤー。例:

- `feat(slack):`, `feat(slack/frontend):`, `fix(slack/backend):`
- 全体共通: `chore:`（scope 省略可）

### 例（実際の履歴より）

```text
feat(slack): ActionCable で Messages/UserChannel を実装し broadcast 統合
docs(slack): docs/architecture.md にシステム図と配信シーケンスを整理
ci: GitHub Actions で各プロジェクトの lint/test を並列実行
chore: projects/ ディレクトリを廃止しサービスディレクトリをリポジトリ直下へ移動
```

---

## コミット粒度

- **1 コミット 1 論理変更**。後で `git revert` できる粒度を意識する
- 「動かない中間状態」を main に残さない（squash merge で吸収するならブランチ内では OK）
- フォーマットだけ / 大量リネームのコミットは独立させる（差分レビューを軽くする）

---

## PR

### タイトル

コミットメッセージと同じ規約 `<type>(<scope>): <概要>`、70 文字以内を目安に。

### 本文テンプレ

```markdown
## Summary
- 何を / なぜ（1〜3 行）

## 変更点
- 主要な変更を箇条書き

## 動作確認
- [ ] ローカルで `npm run lint` / `npx tsc --noEmit` 通過
- [ ] `bundle exec rails test` 通過
- [ ] Playwright E2E 通過（該当範囲のみ）
- [ ] CI green

## 関連
- ADR: <link>
- Issue: <link>
```

設計判断を伴う変更は **対応する ADR を別 PR で先に / 同 PR で同時に** 入れる。

---

## CI

`.github/workflows/ci.yml` で `main` への push と PR で実行:

- `slack-backend`: MySQL + Redis を立ててから `bundle exec rails test`
- `slack-frontend`: `npm ci` → `npm run lint` → `npx tsc --noEmit`
- `slack-ai-worker`: `pip install` → import smoke → `uvicorn` boot + `/health`

**CI red の状態で merge しない**。学習リポでも例外を作らない。

---

## やらないこと

- `--no-verify` で pre-commit / pre-push hook を skip する（pre-commit hook を自前で入れたら必ず通す）
- `git push --force` を `main` に対して実行する
- secret / `.env` / credentials.key 系のファイルをコミットする（`.gitignore` で防ぐ）
- 巨大バイナリ / `node_modules` / `vendor/bundle` のコミット
