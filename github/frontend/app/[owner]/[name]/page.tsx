"use client";

import Link from "next/link";
import { use } from "react";
import { useQuery, gql } from "urql";
import CheckBadge from "@/components/CheckBadge";

const REPO_QUERY = gql`
  query RepositoryOverview($owner: String!, $name: String!) {
    repository(owner: $owner, name: $name) {
      id
      name
      description
      visibility
      viewerPermission
      issues(first: 30) {
        id
        number
        title
        state
        author { login }
      }
      pullRequests(first: 30) {
        id
        number
        title
        state
        checkStatus
        author { login }
      }
    }
  }
`;

type Issue = { id: string; number: number; title: string; state: string; author: { login: string } };
type PR = Issue & { checkStatus: string };

export default function RepoPage({ params }: { params: Promise<{ owner: string; name: string }> }) {
  const { owner, name } = use(params);
  const [{ data, fetching, error }] = useQuery({
    query: REPO_QUERY,
    variables: { owner, name }
  });

  if (fetching) return <p className="text-sm text-zinc-500">loading…</p>;
  if (error) return <p className="text-sm text-red-600">{error.message}</p>;
  if (!data?.repository) return <p className="text-sm text-zinc-500">repository not visible</p>;

  const repo = data.repository;

  return (
    <div className="space-y-6">
      <header className="flex items-center justify-between">
        <h1 className="text-2xl font-bold font-mono">
          <Link href="/" className="text-zinc-500 hover:underline">{owner}</Link>
          <span className="text-zinc-400"> / </span>
          {repo.name}
        </h1>
        <span className="text-xs font-mono text-zinc-500">{repo.viewerPermission}</span>
      </header>

      <section>
        <h2 className="text-lg font-semibold mb-2">Issues ({repo.issues.length})</h2>
        <ul className="divide-y rounded border bg-white">
          {repo.issues.map((i: Issue) => (
            <li key={i.id} className="px-4 py-2 flex items-center justify-between text-sm">
              <div>
                <span className="font-mono text-zinc-500 mr-2">#{i.number}</span>
                <span>{i.title}</span>
              </div>
              <div className="flex items-center gap-3 text-xs text-zinc-500">
                <span className="font-mono">{i.author.login}</span>
                <span className={`px-2 py-0.5 rounded border ${i.state === "OPEN" ? "bg-emerald-50 text-emerald-700 border-emerald-200" : "bg-zinc-100 text-zinc-600 border-zinc-200"}`}>
                  {i.state}
                </span>
              </div>
            </li>
          ))}
          {repo.issues.length === 0 && (
            <li className="px-4 py-3 text-sm text-zinc-500">issue がありません</li>
          )}
        </ul>
      </section>

      <section>
        <h2 className="text-lg font-semibold mb-2">Pull requests ({repo.pullRequests.length})</h2>
        <ul className="divide-y rounded border bg-white">
          {repo.pullRequests.map((p: PR) => (
            <li key={p.id} className="px-4 py-2 flex items-center justify-between text-sm">
              <div>
                <Link
                  href={`/${owner}/${repo.name}/pull/${p.number}`}
                  className="font-mono text-blue-700 mr-2 hover:underline"
                >
                  #{p.number}
                </Link>
                <span>{p.title}</span>
              </div>
              <div className="flex items-center gap-3 text-xs text-zinc-500">
                <CheckBadge state={p.checkStatus} />
                <span className="font-mono">{p.author.login}</span>
                <span className={`px-2 py-0.5 rounded border ${p.state === "OPEN" ? "bg-emerald-50 text-emerald-700 border-emerald-200" : p.state === "MERGED" ? "bg-violet-50 text-violet-700 border-violet-200" : "bg-zinc-100 text-zinc-600 border-zinc-200"}`}>
                  {p.state}
                </span>
              </div>
            </li>
          ))}
          {repo.pullRequests.length === 0 && (
            <li className="px-4 py-3 text-sm text-zinc-500">pull request がありません</li>
          )}
        </ul>
      </section>
    </div>
  );
}
