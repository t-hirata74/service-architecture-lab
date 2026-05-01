"use client";

import Link from "next/link";
import { useState } from "react";
import { useQuery, gql } from "urql";

const ORG_QUERY = gql`
  query OrganizationOverview($login: String!) {
    organization(login: $login) {
      login
      name
      repositories {
        id
        name
        visibility
        viewerPermission
      }
    }
  }
`;

type Repo = { id: string; name: string; visibility: string; viewerPermission: string };

export default function HomePage() {
  const [login, setLogin] = useState("acme");
  const [{ data, fetching, error }] = useQuery({
    query: ORG_QUERY,
    variables: { login }
  });

  return (
    <div className="space-y-6">
      <section className="space-y-2">
        <h1 className="text-2xl font-bold">Organization</h1>
        <p className="text-sm text-zinc-600">
          GraphQL <code>organization(login)</code> を取得します。viewer は右上の switcher で切り替え可能です。
        </p>
        <div className="flex gap-2 items-center">
          <input
            className="border rounded px-2 py-1 text-sm font-mono"
            value={login}
            onChange={(e) => setLogin(e.target.value)}
          />
        </div>
      </section>

      {fetching && <p className="text-sm text-zinc-500">loading…</p>}
      {error && <p className="text-sm text-red-600">{error.message}</p>}

      {data?.organization && (
        <section className="space-y-2">
          <h2 className="text-lg font-semibold">
            {data.organization.name} <span className="text-zinc-500 text-sm">@{data.organization.login}</span>
          </h2>
          <ul className="divide-y rounded border bg-white">
            {data.organization.repositories.map((r: Repo) => (
              <li key={r.id} className="px-4 py-3 flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <Link
                    href={`/${data.organization.login}/${r.name}`}
                    className="font-mono text-blue-700 hover:underline"
                  >
                    {data.organization.login}/{r.name}
                  </Link>
                  <span className="text-xs px-2 py-0.5 rounded bg-zinc-100 text-zinc-600">
                    {r.visibility.toLowerCase()}
                  </span>
                </div>
                <span className="text-xs font-mono text-zinc-500">{r.viewerPermission}</span>
              </li>
            ))}
            {data.organization.repositories.length === 0 && (
              <li className="px-4 py-3 text-sm text-zinc-500">visible なリポジトリがありません</li>
            )}
          </ul>
        </section>
      )}

      {data && !data.organization && (
        <p className="text-sm text-zinc-500">organization not found</p>
      )}
    </div>
  );
}
