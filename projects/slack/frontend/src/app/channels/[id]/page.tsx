"use client";

import { useEffect, useRef, useState } from "react";
import { useParams } from "next/navigation";
import { fetchMessages, postMessage, type Message } from "@/lib/messages";

export default function ChannelDetailPage() {
  const params = useParams<{ id: string }>();
  const channelId = Number(params.id);
  const [messages, setMessages] = useState<Message[]>([]);
  const [body, setBody] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const listRef = useRef<HTMLUListElement | null>(null);

  useEffect(() => {
    if (!channelId) return;
    let cancelled = false;
    fetchMessages(channelId)
      .then((data) => {
        if (cancelled) return;
        // API は降順 (新しい順) で返すので表示用に昇順へ反転
        setMessages([...data.messages].reverse());
      })
      .catch((err) => !cancelled && setError(err instanceof Error ? err.message : String(err)));
    return () => {
      cancelled = true;
    };
  }, [channelId]);

  useEffect(() => {
    listRef.current?.scrollTo({ top: listRef.current.scrollHeight });
  }, [messages]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    const text = body.trim();
    if (!text) return;
    setSubmitting(true);
    setError(null);
    try {
      const msg = await postMessage(channelId, text);
      setMessages((prev) => [...prev, msg]);
      setBody("");
    } catch (err) {
      setError(err instanceof Error ? err.message : "投稿に失敗しました");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <>
      <ul ref={listRef} className="flex-1 space-y-3 overflow-y-auto px-4 py-4">
        {messages.map((msg) => (
          <li key={msg.id} className="space-y-1" data-testid="message">
            <div className="flex items-baseline gap-2">
              <span className="font-semibold">{msg.user.display_name}</span>
              <time className="text-xs text-slate-500">
                {new Date(msg.created_at).toLocaleTimeString()}
              </time>
            </div>
            <p className="text-sm">{msg.body}</p>
          </li>
        ))}
        {messages.length === 0 && (
          <li className="text-sm text-slate-500">まだメッセージはありません。</li>
        )}
      </ul>

      {error && (
        <div role="alert" className="border-t border-red-200 bg-red-50 px-4 py-2 text-sm text-red-700">
          {error}
        </div>
      )}

      <form
        onSubmit={handleSubmit}
        className="border-t border-slate-200 bg-white p-3 dark:border-slate-800 dark:bg-slate-900"
      >
        <div className="flex gap-2">
          <input
            type="text"
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder="メッセージを入力…"
            aria-label="メッセージ"
            className="flex-1 rounded border border-slate-300 bg-white px-3 py-2 text-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 dark:border-slate-700 dark:bg-slate-950"
          />
          <button
            type="submit"
            disabled={submitting}
            className="rounded bg-indigo-600 px-4 py-2 text-sm text-white hover:bg-indigo-700 disabled:opacity-50"
          >
            送信
          </button>
        </div>
      </form>
    </>
  );
}
