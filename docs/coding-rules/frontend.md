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

- `lib/api.ts` の wrapper を経由する（JWT / Token を localStorage から取得して `Authorization` ヘッダに自動付与）
- 認証エラー / バリデーションエラーは `error` / `field-error` フィールドに従って `lib/auth.ts` のような形でパースして throw
- リアルタイム購読は `lib/cable.ts` の singleton consumer を使う（複数生成しない）
- **401 を受けたら自動 logout + `/login` に redirect** (instagram で確立): token 失効・サーバ側削除でアクセス不能になったら無限ループせずに login 画面へ戻す。`/auth/login` `/auth/register` は除外:
  ```tsx
  if (res.status === 401 && typeof window !== "undefined" &&
      !path.startsWith("/auth/login") && !path.startsWith("/auth/register")) {
    if (window.localStorage.getItem(TOKEN_KEY)) {
      clearAuth();
      window.location.href = "/login";   // hard navigate で in-flight effect を中断
    }
    throw new ApiError(401, "unauthorized");
  }
  ```
  実例: `instagram/frontend/src/lib/api.ts:apiFetch`。

### REST + OpenAPI のプロジェクト

[`api-style.md`](../api-style.md) で REST + OpenAPI を採用するプロジェクト
（slack / youtube）では:

- **`openapi-typescript` で `backend/docs/openapi.yml` から TS 型を自動生成**
- 生成先: `src/lib/api-types.ts`（git 管理）
- `lib/<domain>.ts` 内の手書き型は撤去し、生成された型を import
- スキーマ更新時は `npm run gen:api` を走らせて regenerate → diff をコミット
- `tsc --noEmit` で乖離が即検知される

### GraphQL のプロジェクト（github 等）

- スキーマ駆動でクライアントを生成（`graphql-codegen` 等。プロジェクト着手時に確定）
- 単一エンドポイント `/graphql` に POST。`urql` か `@apollo/client` のどちらかを ADR で選定
- `lib/<domain>.ts` の代わりに **operation ファイル**（`.graphql` / `.gql`）でクエリを定義

---

## サーバー / クライアントコンポーネント

- App Router のデフォルト（Server Component）を活かし、`"use client"` は**必要な所だけ**付ける
- 必要な所 = `useState`/`useEffect`/イベントハンドラ / ActionCable 購読 / localStorage アクセス
- ページの「データ取得 → 表示」は Server Component、インタラクションのある部分だけ子の Client Component に切り出す

### Next 16 で踏んだ落とし穴

- **`useSearchParams` を使うクライアントコンポーネントは `<Suspense>` で必ずラップ**。
  Server Component から子として import する場合、ラップしないとビルドが落ちる:
  ```tsx
  <Suspense fallback={<div className="flex-1" />}>
    <SearchBar />
  </Suspense>
  ```
- **`react-hooks/set-state-in-effect` ルール**: `useEffect` 内で `setState` を直接呼ぶと
  ESLint エラー。fetch + cancel パターンに置き換える:
  ```tsx
  useEffect(() => {
    let cancelled = false;
    fetchData().then((d) => { if (!cancelled) setData(d); });
    return () => { cancelled = true; };
  }, [deps]);
  ```
- 詳細は `<service>/frontend/AGENTS.md` に「学習データに無いバージョン」の警告がある。書く前に `node_modules/next/dist/docs/` を読む。

---

## urql Provider pattern (GraphQL プロジェクト)

github プロジェクト (ADR 0001) で確立した構成。GraphQL を使う今後のプロジェクトはここから始める。

### Client は `useState` initializer で 1 度だけ生成

```tsx
"use client";
import { useState } from "react";
import { Provider, Client, cacheExchange, fetchExchange } from "urql";
import { getViewerLogin } from "@/lib/viewer";

const GRAPHQL_URL = process.env.NEXT_PUBLIC_GRAPHQL_URL ?? "http://127.0.0.1:3030/graphql";

function createClient(): Client {
  return new Client({
    url: GRAPHQL_URL,
    exchanges: [cacheExchange, fetchExchange],
    fetchOptions: () => {
      // localStorage / cookie を fetch のたびに読み直す (auth 切替で client を再生成しない)
      const login = typeof window !== "undefined" ? getViewerLogin() : null;
      const headers: Record<string, string> = { "Content-Type": "application/json" };
      if (login) headers["X-User-Login"] = login;
      return { headers };
    },
    requestPolicy: "cache-and-network"
  });
}

export default function UrqlProvider({ children }: { children: React.ReactNode }) {
  const [client] = useState<Client>(() => createClient());
  return <Provider value={client}>{children}</Provider>;
}
```

**やらないこと**: モジュール singleton (`let _client: Client | null`) で生成する。`"use client"` でも Next.js は SSR で 1 度評価されるため、シングルトンが SSR と CSR で残り続けて事故る。`useState` 初期化なら確実に新しい Client が CSR 側で生まれる。

### urql は queries に GET を使う

backend 側の API ルーティング / CORS が GET を許可していないと **`[Network] Failed to fetch`** で詰まる。これを E2E 直前に踏むと原因特定に時間が溶けるので、最初から両方許可する:

- Rails: `match "/graphql", via: %i[get post]`
- CORS: `methods: %i[get post options]`

詳細は [api-style.md](../api-style.md#graphql-の運用github-プロジェクトで確立) を参照。

### codegen 出力は commit する

`codegen.ts` で生成した型ファイル (`lib/gql/types.ts` 等) は **commit して**、CI で `git diff --exit-code` を実行する。
さもないと「型付き hooks がある」という前提が壊れたまま開発が進む。OpenAPI の `npm run gen:api` と同じ思想。

### サンプル位置

- `github/frontend/components/UrqlProvider.tsx`
- `github/frontend/codegen.ts`
- `github/frontend/lib/viewer.ts` (auth header 切替の例)

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
