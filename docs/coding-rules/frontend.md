# Frontend コーディング規約 (React / Next.js)

`slack/frontend/` で実際に採用している規約を共通ルールとしてまとめる。  
新規プロジェクトは原則これに従い、外れる場合はプロジェクト内の `frontend/CLAUDE.md` などで明記する。

---

## 技術スタック

- Next.js 16 (App Router) / React 19 / TypeScript / Tailwind v4
- ESLint 9 (flat config, `eslint-config-next/core-web-vitals` + `eslint-config-next/typescript`)
- 状態管理は標準（`useState`/`useReducer`/`Context`）から始め、必要になったら追加する。先回りで Zustand / TanStack Query などを入れない

> ⚠️ **Next.js 16 は破壊的変更を含む**。学習データに無いため、書く前に `node_modules/next/dist/docs/` の該当ガイドを必ず確認する（`slack/frontend/AGENTS.md` 参照）。

---

## TypeScript

- `tsconfig.json` の `strict: true` を**外さない**
- `any` は禁止。型が分からない場合は `unknown` から narrow する
- パスエイリアス `@/*` → `./src/*` を使用。相対パス `../../../` を 3 階層以上重ねない
- API レスポンスは `lib/*.ts` で型を export し、ページ側はその型を import して使う

---

## ディレクトリ構成

```text
src/
  app/                # App Router（pages = route）
    layout.tsx
    page.tsx
    <segment>/
      page.tsx
      [id]/page.tsx
  lib/                # API クライアント・ドメインロジック
    api.ts            # fetch wrapper、JWT 注入
    auth.ts           # signup/login/logout/fetchMe
    cable.ts          # ActionCable singleton
    <domain>.ts       # channels.ts, messages.ts, summary.ts ...
```

- `components/` は**最初は作らない**。ページ内に書いてしまい、3 箇所以上で使い回しが発生してから抽出する
- ドメインごとに 1 ファイル `lib/<domain>.ts`：型 export + fetch 関数を集約。コンポーネントから直接 `fetch` を呼ばない

---

## API 通信

- `lib/api.ts` の wrapper を経由する（JWT を localStorage から取得して `Authorization` ヘッダに自動付与）
- 認証エラー / バリデーションエラーは `error` / `field-error` フィールドに従って `lib/auth.ts` のような形でパースして throw
- リアルタイム購読は `lib/cable.ts` の singleton consumer を使う（複数生成しない）

---

## サーバー / クライアントコンポーネント

- App Router のデフォルト（Server Component）を活かし、`"use client"` は**必要な所だけ**付ける
- 必要な所 = `useState`/`useEffect`/イベントハンドラ / ActionCable 購読 / localStorage アクセス
- ページの「データ取得 → 表示」は Server Component、インタラクションのある部分だけ子の Client Component に切り出す

---

## スタイリング (Tailwind v4)

- Tailwind ユーティリティを基本とし、`globals.css` には CSS 変数とリセットだけ書く
- 同じクラス組が 3 箇所以上で繰り返される場合のみコンポーネント抽出 or `@apply`

---

## エラー処理 / ユーザー入力

- 「あり得ない」入力に対する防御コードを書かない（バックエンド境界は別）
- フォームのバリデーションエラーはサーバーから返るメッセージをそのまま表示する方針。クライアント側で重複バリデーションを書かない

---

## Lint / 型チェック

- ローカル: `npm run lint` / `npx tsc --noEmit`
- CI でも同じ 2 つを実行（`.github/workflows/ci.yml`）
- ESLint warning でも放置しない。`// eslint-disable-next-line` を使う場合は必ず理由をコメント

---

## やらないこと

- **絵文字ピッカー / リッチテキストエディタ / 凝ったアニメーション**：CLAUDE.md の「除外」スコープ
- **i18n / a11y 網羅**：1 言語 / 標準的なセマンティクスで十分
- **不要な抽象化**：3 個以上似たコードが出るまで共通化しない
