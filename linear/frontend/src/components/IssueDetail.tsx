'use client';

import { useEffect, useState } from 'react';
import { appendOrderKey } from '@linear/shared';
import type { SyncOp, TriageResponse } from '@linear/shared';
import { issueActivity, triageIssue } from '@/lib/api';
import { identifier, PRIORITIES } from '@/lib/issue-utils';
import { useSync } from '@/lib/sync-provider';

const LABEL_COLORS = ['#ef4444', '#f97316', '#eab308', '#22c55e', '#3b82f6', '#8b5cf6'];

/**
 * issue 詳細パネル。呼び出し側が key={issueId} で remount するため、
 * useState の初期値が issue 切替時の初期化を担う (effect での setState を避ける)。
 */
export function IssueDetail({
  issueId,
  onClose,
}: {
  issueId: number;
  onClose: () => void;
}) {
  const { state, mutate, session, online } = useSync();
  const issue = state.issues[issueId];
  const team = issue ? state.teams[issue.teamId] : undefined;

  const [title, setTitle] = useState(issue?.title ?? '');
  const [comment, setComment] = useState('');
  const [newLabel, setNewLabel] = useState('');
  const [triage, setTriage] = useState<TriageResponse | null>(null);
  const [activity, setActivity] = useState<SyncOp[] | null>(null);

  // activity feed = sync_ops の projection (server 側に専用テーブルなし)。
  // 自分の変更が確定するたび (updatedAt 変化) に取り直す
  const updatedAt = issue?.updatedAt;
  useEffect(() => {
    if (issueId <= 0) return;
    let cancelled = false;
    issueActivity(session.workspace.id, issueId)
      .then((r) => {
        if (!cancelled) setActivity(r.ops);
      })
      .catch(() => {
        if (!cancelled) setActivity([]);
      });
    return () => {
      cancelled = true;
    };
  }, [issueId, session.workspace.id, updatedAt]);

  if (!issue || !team) {
    return null; // 削除された (op が先に届いた) 場合など
  }

  const states = Object.values(state.states)
    .filter((s) => s.teamId === issue.teamId)
    .sort((a, b) => a.position - b.position);
  const teamLabels = Object.values(state.labels)
    .filter((l) => l.teamId === issue.teamId)
    .sort((a, b) => a.id - b.id);
  const attached = new Set(
    state.issueLabels.filter((il) => il.issueId === issue.id).map((il) => il.labelId),
  );
  const comments = Object.values(state.comments)
    .filter((c) => c.issueId === issue.id)
    .sort((a, b) => (a.createdAt < b.createdAt ? -1 : 1));
  const userName = (id: number) => state.users[id]?.name ?? `user#${id}`;

  const commitTitle = () => {
    const next = title.trim();
    if (next && next !== issue.title) {
      mutate({ type: 'updateIssue', issueId: issue.id, patch: { title: next } });
    }
  };

  return (
    <aside
      data-testid="issue-detail"
      className="fixed inset-y-0 right-0 z-10 flex w-96 flex-col gap-4 overflow-y-auto border-l border-zinc-200 bg-white p-4 shadow-xl"
    >
      <header className="flex items-center justify-between text-xs text-zinc-400">
        <span>{identifier(issue, team)}</span>
        <button onClick={onClose} className="rounded px-2 py-1 hover:bg-zinc-100">
          閉じる ✕
        </button>
      </header>

      <input
        data-testid="detail-title"
        className="rounded-md border border-transparent px-2 py-1 text-base font-medium hover:border-zinc-200 focus:border-indigo-400 focus:outline-none"
        value={title}
        onChange={(e) => setTitle(e.target.value)}
        onBlur={commitTitle}
        onKeyDown={(e) => e.key === 'Enter' && commitTitle()}
      />

      <div className="grid grid-cols-2 gap-2 text-xs">
        <label className="flex flex-col gap-1 text-zinc-500">
          状態
          <select
            data-testid="detail-state"
            className="rounded-md border border-zinc-300 px-2 py-1 text-sm text-zinc-900"
            value={issue.stateId}
            onChange={(e) =>
              mutate({
                type: 'moveIssue',
                issueId: issue.id,
                stateId: Number(e.target.value),
                sortOrder: appendOrderKey(state, issue.teamId, Number(e.target.value)),
              })
            }
          >
            {states.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-zinc-500">
          優先度
          <select
            data-testid="detail-priority"
            className="rounded-md border border-zinc-300 px-2 py-1 text-sm text-zinc-900"
            value={issue.priority}
            onChange={(e) =>
              mutate({
                type: 'updateIssue',
                issueId: issue.id,
                patch: { priority: Number(e.target.value) },
              })
            }
          >
            {PRIORITIES.map((p) => (
              <option key={p.value} value={p.value}>
                {p.label}
              </option>
            ))}
          </select>
        </label>
      </div>

      {issue.description && (
        <p className="rounded-md bg-zinc-50 p-2 text-sm whitespace-pre-wrap">
          {issue.description}
        </p>
      )}

      <section className="text-xs">
        <h3 className="mb-1 font-semibold text-zinc-500">ラベル</h3>
        <div className="flex flex-wrap gap-1">
          {teamLabels.map((l) => (
            <button
              key={l.id}
              onClick={() =>
                mutate(
                  attached.has(l.id)
                    ? { type: 'removeIssueLabel', issueId: issue.id, labelId: l.id }
                    : { type: 'addIssueLabel', issueId: issue.id, labelId: l.id },
                )
              }
              className={`rounded-full border px-2 py-0.5 ${
                attached.has(l.id)
                  ? 'border-transparent text-white'
                  : 'border-zinc-300 text-zinc-500'
              }`}
              style={attached.has(l.id) ? { backgroundColor: l.color } : {}}
            >
              {l.name}
            </button>
          ))}
          <form
            className="contents"
            onSubmit={(e) => {
              e.preventDefault();
              const name = newLabel.trim();
              if (!name) return;
              mutate({
                type: 'createLabel',
                teamId: issue.teamId,
                name,
                color: LABEL_COLORS[teamLabels.length % LABEL_COLORS.length]!,
              });
              setNewLabel('');
            }}
          >
            <input
              className="w-20 rounded-full border border-dashed border-zinc-300 px-2 py-0.5"
              placeholder="+ 追加"
              value={newLabel}
              onChange={(e) => setNewLabel(e.target.value)}
            />
          </form>
        </div>
      </section>

      <section className="text-xs">
        <div className="mb-1 flex items-center gap-2">
          <h3 className="font-semibold text-zinc-500">AI triage</h3>
          <button
            data-testid="ai-triage"
            disabled={issue.id < 0 || !online}
            onClick={() =>
              void triageIssue(session.workspace.id, issue.id).then(setTriage)
            }
            className="rounded-md border border-zinc-300 px-2 py-0.5 hover:bg-zinc-50 disabled:opacity-40"
          >
            提案を取得
          </button>
        </div>
        {triage &&
          (triage.available && triage.suggestion ? (
            <div className="rounded-md bg-indigo-50 p-2">
              <p>
                優先度 {PRIORITIES[triage.suggestion.priority]?.label} / ラベル{' '}
                {triage.suggestion.labels.join(', ') || 'なし'} —{' '}
                {triage.suggestion.reason}
              </p>
              {triage.suggestion.duplicateIssueIds.length > 0 && (
                <p className="mt-1 text-amber-700">
                  重複候補:{' '}
                  {triage.suggestion.duplicateIssueIds
                    .map((id) => {
                      const dup = state.issues[id];
                      return dup ? identifier(dup, state.teams[dup.teamId]) : `#${id}`;
                    })
                    .join(', ')}
                </p>
              )}
              <button
                onClick={() =>
                  mutate({
                    type: 'updateIssue',
                    issueId: issue.id,
                    patch: { priority: triage.suggestion!.priority },
                  })
                }
                className="mt-1 rounded bg-indigo-600 px-2 py-0.5 text-white"
              >
                優先度を適用
              </button>
            </div>
          ) : (
            <p className="text-zinc-400">ai-worker が応答しません (degraded)</p>
          ))}
      </section>

      <section className="text-xs">
        <h3 className="mb-1 font-semibold text-zinc-500">
          コメント ({comments.length})
        </h3>
        <ul className="space-y-2">
          {comments.map((c) => (
            <li key={c.id} className="rounded-md bg-zinc-50 p-2">
              <p className="mb-0.5 text-[10px] text-zinc-400">
                {userName(c.authorId)}
                {c.id < 0 && ' ・保存中…'}
              </p>
              <p className="text-sm whitespace-pre-wrap">{c.body}</p>
            </li>
          ))}
        </ul>
        <form
          className="mt-2 flex gap-1"
          onSubmit={(e) => {
            e.preventDefault();
            const body = comment.trim();
            if (!body) return;
            mutate({ type: 'createComment', issueId: issue.id, body });
            setComment('');
          }}
        >
          <input
            data-testid="comment-input"
            className="flex-1 rounded-md border border-zinc-300 px-2 py-1"
            placeholder="コメントを書く…"
            value={comment}
            onChange={(e) => setComment(e.target.value)}
          />
          <button
            data-testid="comment-submit"
            className="rounded-md bg-zinc-800 px-2 py-1 text-white"
          >
            送信
          </button>
        </form>
      </section>

      <section className="text-xs">
        <h3 className="mb-1 font-semibold text-zinc-500">アクティビティ</h3>
        {activity === null ? (
          <p className="text-zinc-400">読み込み中…</p>
        ) : (
          <ul className="space-y-1 text-zinc-500">
            {activity.map((op) => (
              <li key={op.seq}>
                <span className="text-zinc-400">#{op.seq}</span>{' '}
                {userName(op.actorId)} が{' '}
                {op.action === 'insert'
                  ? '作成'
                  : op.action === 'delete'
                    ? '削除'
                    : `更新 (${Object.keys(op.payload)
                        .filter((k) => k !== 'updatedAt')
                        .join(', ')})`}
              </li>
            ))}
          </ul>
        )}
      </section>
    </aside>
  );
}
