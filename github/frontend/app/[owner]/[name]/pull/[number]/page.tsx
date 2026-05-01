"use client";

import Link from "next/link";
import { use } from "react";
import { useQuery, gql } from "urql";
import CheckBadge from "@/components/CheckBadge";

const PR_QUERY = gql`
  query PullRequestDetail($owner: String!, $name: String!, $number: Int!) {
    pullRequest(owner: $owner, name: $name, number: $number) {
      id
      number
      title
      body
      state
      mergeableState
      headRef
      baseRef
      headSha
      checkStatus
      author { login }
      requestedReviewers { login }
      reviews { id state body reviewer { login } createdAt }
      commitChecks { id name state output }
    }
  }
`;

type Review = { id: string; state: string; body: string; reviewer: { login: string }; createdAt: string };
type CommitCheck = { id: string; name: string; state: string; output: string | null };
type User = { login: string };

export default function PullRequestPage({
  params
}: {
  params: Promise<{ owner: string; name: string; number: string }>;
}) {
  const { owner, name, number } = use(params);
  const [{ data, fetching, error }] = useQuery({
    query: PR_QUERY,
    variables: { owner, name, number: Number(number) }
  });

  if (fetching) return <p className="text-sm text-zinc-500">loading…</p>;
  if (error) return <p className="text-sm text-red-600">{error.message}</p>;
  if (!data?.pullRequest) return <p className="text-sm text-zinc-500">pull request not visible</p>;

  const pr = data.pullRequest;

  return (
    <div className="space-y-6">
      <header className="space-y-2">
        <div className="text-sm text-zinc-500 font-mono">
          <Link href="/" className="hover:underline">{owner}</Link>
          <span> / </span>
          <Link href={`/${owner}/${name}`} className="hover:underline">{name}</Link>
        </div>
        <h1 className="text-2xl font-bold">
          <span className="text-zinc-400 font-mono mr-2">#{pr.number}</span>
          {pr.title}
        </h1>
        <div className="flex flex-wrap items-center gap-3 text-xs">
          <span className={`px-2 py-0.5 rounded border ${pr.state === "OPEN" ? "bg-emerald-50 text-emerald-700 border-emerald-200" : pr.state === "MERGED" ? "bg-violet-50 text-violet-700 border-violet-200" : "bg-zinc-100 text-zinc-600 border-zinc-200"}`}>
            {pr.state}
          </span>
          <span className="px-2 py-0.5 rounded border bg-zinc-50 text-zinc-700 border-zinc-200 font-mono">
            {pr.mergeableState}
          </span>
          <CheckBadge state={pr.checkStatus} />
          <span className="font-mono text-zinc-500">
            {pr.author.login} wants to merge {pr.headRef} → {pr.baseRef} ({pr.headSha.slice(0, 7)})
          </span>
        </div>
      </header>

      {pr.body && (
        <section className="border bg-white rounded p-4 text-sm whitespace-pre-wrap">{pr.body}</section>
      )}

      <section>
        <h2 className="text-lg font-semibold mb-2">CI checks ({pr.commitChecks.length})</h2>
        <table className="w-full text-sm border bg-white rounded overflow-hidden">
          <thead className="bg-zinc-100 text-zinc-600">
            <tr>
              <th className="text-left px-3 py-2 font-medium">name</th>
              <th className="text-left px-3 py-2 font-medium">state</th>
              <th className="text-left px-3 py-2 font-medium">output</th>
            </tr>
          </thead>
          <tbody className="divide-y">
            {pr.commitChecks.map((c: CommitCheck) => (
              <tr key={c.id}>
                <td className="px-3 py-2 font-mono">{c.name}</td>
                <td className="px-3 py-2"><CheckBadge state={c.state} /></td>
                <td className="px-3 py-2 text-zinc-600">{c.output ?? "—"}</td>
              </tr>
            ))}
            {pr.commitChecks.length === 0 && (
              <tr>
                <td colSpan={3} className="px-3 py-3 text-zinc-500">
                  まだ check が登録されていません。ai-worker の <code>POST /check/run</code> から流し込んでください。
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </section>

      <section>
        <h2 className="text-lg font-semibold mb-2">Requested reviewers</h2>
        <div className="flex gap-2 flex-wrap">
          {pr.requestedReviewers.map((u: User) => (
            <span key={u.login} className="text-xs px-2 py-1 rounded bg-amber-50 border border-amber-200 font-mono">
              {u.login}
            </span>
          ))}
          {pr.requestedReviewers.length === 0 && (
            <span className="text-sm text-zinc-500">指定されていません</span>
          )}
        </div>
      </section>

      <section>
        <h2 className="text-lg font-semibold mb-2">Reviews ({pr.reviews.length})</h2>
        <ul className="space-y-2">
          {pr.reviews.map((r: Review) => (
            <li key={r.id} className="border bg-white rounded p-3 text-sm">
              <div className="flex items-center justify-between mb-1">
                <span className="font-mono text-zinc-700">{r.reviewer.login}</span>
                <span className={`text-xs px-2 py-0.5 rounded border ${r.state === "APPROVED" ? "bg-emerald-50 text-emerald-700 border-emerald-200" : r.state === "CHANGES_REQUESTED" ? "bg-rose-50 text-rose-700 border-rose-200" : "bg-zinc-100 text-zinc-600 border-zinc-200"}`}>
                  {r.state}
                </span>
              </div>
              {r.body && <div className="text-zinc-700 whitespace-pre-wrap">{r.body}</div>}
            </li>
          ))}
          {pr.reviews.length === 0 && (
            <li className="text-sm text-zinc-500">レビューはまだありません</li>
          )}
        </ul>
      </section>
    </div>
  );
}
