'use client';

import { useState } from 'react';
import { useSync } from '@/lib/sync-provider';

/**
 * メンバー一覧 + 招待/除外 (E1 / ADR 0006)。
 * 招待は server-resolved コマンドのため楽観反映されず、確定 op で行が増える。
 */
export function MembersPanel({ onClose }: { onClose: () => void }) {
  const { state, mutate, session } = useSync();
  const [email, setEmail] = useState('');
  const [role, setRole] = useState<'member' | 'admin'>('member');

  const members = [...state.members].sort((a, b) => a.userId - b.userId);
  const myRole = members.find((m) => m.userId === session.user.id)?.role;

  return (
    <div
      className="fixed inset-0 z-20 flex items-start justify-center bg-zinc-900/30 pt-32"
      onClick={onClose}
    >
      <div
        data-testid="members-panel"
        onClick={(e) => e.stopPropagation()}
        className="w-110 rounded-xl border border-zinc-200 bg-white p-4 shadow-xl"
      >
        <h2 className="mb-3 text-sm font-semibold">
          メンバー ({members.length})
        </h2>
        <ul className="mb-3 space-y-1">
          {members.map((m) => {
            const name = state.users[m.userId]?.name ?? `user#${m.userId}`;
            return (
              <li
                key={m.userId}
                data-testid="member-row"
                data-member-name={name}
                className="flex items-center gap-2 rounded-md px-2 py-1 text-sm hover:bg-zinc-50"
              >
                <span>{name}</span>
                <span className="rounded-full bg-zinc-100 px-2 text-[10px] text-zinc-500">
                  {m.role}
                </span>
                {m.userId === session.user.id && (
                  <span className="text-[10px] text-zinc-400">(自分)</span>
                )}
                {myRole === 'admin' && m.userId !== session.user.id && (
                  <button
                    data-testid="member-remove"
                    onClick={() =>
                      mutate({ type: 'removeMember', userId: m.userId })
                    }
                    className="ml-auto text-xs text-zinc-400 hover:text-red-600"
                  >
                    除外
                  </button>
                )}
              </li>
            );
          })}
        </ul>
        {myRole === 'admin' ? (
          <form
            className="flex gap-1"
            onSubmit={(e) => {
              e.preventDefault();
              const value = email.trim();
              if (!value) return;
              mutate({ type: 'inviteMember', email: value, role });
              setEmail('');
            }}
          >
            <input
              data-testid="invite-email"
              type="email"
              required
              className="flex-1 rounded-md border border-zinc-300 px-2 py-1 text-sm"
              placeholder="登録済みユーザの email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
            <select
              data-testid="invite-role"
              className="rounded-md border border-zinc-300 px-1 py-1 text-xs"
              value={role}
              onChange={(e) => setRole(e.target.value as 'member' | 'admin')}
            >
              <option value="member">member</option>
              <option value="admin">admin</option>
            </select>
            <button
              data-testid="invite-submit"
              className="rounded-md bg-indigo-600 px-3 py-1 text-xs font-medium text-white hover:bg-indigo-500"
            >
              招待
            </button>
          </form>
        ) : (
          <p className="text-xs text-zinc-400">招待・除外は admin のみ行えます</p>
        )}
      </div>
    </div>
  );
}
