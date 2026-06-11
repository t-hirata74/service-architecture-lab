'use client';

import { useState } from 'react';
import { useSync } from '@/lib/sync-provider';
import { PRIORITIES } from '@/lib/issue-utils';

export function NewIssueDialog({
  teamId,
  stateId,
  onClose,
}: {
  teamId: number;
  stateId: number;
  onClose: () => void;
}) {
  const { mutate } = useSync();
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [priority, setPriority] = useState(0);

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!title.trim()) return;
    // 楽観適用で即座にカードが現れる (ADR 0003)。server 確定で番号が付く
    mutate({
      type: 'createIssue',
      teamId,
      stateId,
      title: title.trim(),
      ...(description.trim() ? { description: description.trim() } : {}),
      priority,
    });
    onClose();
  };

  return (
    <div
      className="fixed inset-0 z-20 flex items-start justify-center bg-zinc-900/30 pt-32"
      onClick={onClose}
    >
      <form
        data-testid="new-issue-dialog"
        onClick={(e) => e.stopPropagation()}
        onSubmit={submit}
        className="w-130 rounded-xl border border-zinc-200 bg-white p-4 shadow-xl"
      >
        <h2 className="mb-3 text-sm font-semibold">新しい issue</h2>
        <input
          data-testid="new-issue-title"
          autoFocus
          className="mb-2 w-full rounded-md border border-zinc-300 px-3 py-2 text-sm"
          placeholder="タイトル"
          value={title}
          onChange={(e) => setTitle(e.target.value)}
        />
        <textarea
          data-testid="new-issue-description"
          className="mb-2 w-full rounded-md border border-zinc-300 px-3 py-2 text-sm"
          placeholder="説明 (任意)"
          rows={3}
          value={description}
          onChange={(e) => setDescription(e.target.value)}
        />
        <div className="flex items-center justify-between">
          <select
            className="rounded-md border border-zinc-300 px-2 py-1 text-xs"
            value={priority}
            onChange={(e) => setPriority(Number(e.target.value))}
          >
            {PRIORITIES.map((p) => (
              <option key={p.value} value={p.value}>
                {p.label}
              </option>
            ))}
          </select>
          <div className="flex gap-2">
            <button
              type="button"
              onClick={onClose}
              className="rounded-md px-3 py-1.5 text-xs text-zinc-500 hover:bg-zinc-100"
            >
              キャンセル
            </button>
            <button
              data-testid="new-issue-submit"
              type="submit"
              className="rounded-md bg-indigo-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-indigo-500"
            >
              作成
            </button>
          </div>
        </div>
      </form>
    </div>
  );
}
