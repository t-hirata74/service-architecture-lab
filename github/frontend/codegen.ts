import type { CodegenConfig } from "@graphql-codegen/cli";

// ADR 0001: backend GraphQL schema を SDL で取り込み、urql 用 hooks を自動生成。
// schema 更新は backend 側で `bundle exec rake graphql:dump_schema` を実行する想定。
const config: CodegenConfig = {
  schema: "../backend/docs/schema.graphql",
  documents: ["app/**/*.{ts,tsx}", "lib/**/*.{ts,tsx}"],
  generates: {
    "lib/gql/types.ts": {
      plugins: ["typescript", "typescript-operations", "typescript-urql"],
      config: {
        skipTypename: false,
        withHooks: true,
        scalars: { ID: "string", ISO8601DateTime: "string" }
      }
    }
  }
};

export default config;
