"use client";

import { useEffect, useRef, useState } from "react";
import { useParams } from "next/navigation";
import { fetchMessages, postMessage, type Message } from "@/lib/messages";
import { markChannelRead } from "@/lib/channels";
import { getCableConsumer } from "@/lib/cable";

export default function ChannelDetailPage() {
  const params = useParams<{ id: string }>();
  const channelId = Number(params.id);
  const [messages, setMessages] = useState<Message[]>([]);
  const [body, setBody] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const listRef = useRef<HTMLUListElement | null>(null);
  const lastSentReadRef = useRef<number>(0);

  // ADR 0002: チャンネル切替で送信済みカーソル状態をリセット
  useEffect(() => {
    lastSentReadRef.current = 0;
  }, [channelId]);

  // ADR 0002: 表示中の最新メッセージで既読 cursor を進める (単調増加で重複送信を回避)
  useEffect(() => {
    if (!channelId || messages.length === 0) return;
    const latest = messages[messages.length - 1].id;
    if (latest <= lastSentReadRef.current) return;
    lastSentReadRef.current = latest;
    void markChannelRead(channelId, latest).catch((err) =>
      console.error("既読更新失敗", err),
    );
  }, [messages, channelId]);

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

  // ADR 0001: MessagesChannel 購読でリアルタイム受信
  useEffect(() => {
    if (!channelId) return;
    const subscription = getCableConsumer().subscriptions.create(
      { channel: "MessagesChannel", channel_id: channelId },
      {
        received(data: { type: string; message?: Message }) {
          if (data.type === "message.created" && data.message) {
            const incoming = data.message;
            setMessages((prev) => {
              // 自分が投稿してすぐ optimistic に追加した可能性があるので id で dedup
              if (prev.some((m) => m.id === incoming.id)) return prev;
              return [...prev, incoming];
            });
          }
        },
      },
    );
    return () => {
      subscription.unsubscribe();
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
      // optimistic 追加はせず broadcast 経由の単一経路に揃える (dedup による重複防止が破綻するため)
      await postMessage(channelId, text);
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
