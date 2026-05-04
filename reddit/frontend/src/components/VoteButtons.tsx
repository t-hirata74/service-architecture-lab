"use client";

import { useState } from "react";

type Props = {
  initialScore: number;
  onVote: (value: -1 | 0 | 1) => Promise<{ score: number; user_value: number }>;
};

export function VoteButtons({ initialScore, onVote }: Props) {
  const [score, setScore] = useState(initialScore);
  const [myValue, setMyValue] = useState<-1 | 0 | 1>(0);
  const [busy, setBusy] = useState(false);

  const cast = async (target: -1 | 1) => {
    if (busy) return;
    setBusy(true);
    try {
      const next = myValue === target ? 0 : target;
      const res = await onVote(next);
      setScore(res.score);
      setMyValue(next);
    } catch {
      // 401 etc は api.ts 側で /login にリダイレクト
    } finally {
      setBusy(false);
    }
  };

  const upActive = myValue === 1;
  const downActive = myValue === -1;

  return (
    <div className="flex flex-col items-center w-10 select-none">
      <button
        type="button"
        aria-label="upvote"
        onClick={() => cast(1)}
        className={`text-lg leading-none ${upActive ? "text-[var(--accent)]" : "text-[var(--muted)] hover:text-[var(--accent)]"}`}
      >
        ▲
      </button>
      <span className="text-sm font-bold tabular-nums">{score}</span>
      <button
        type="button"
        aria-label="downvote"
        onClick={() => cast(-1)}
        className={`text-lg leading-none ${downActive ? "text-blue-500" : "text-[var(--muted)] hover:text-blue-500"}`}
      >
        ▼
      </button>
    </div>
  );
}
