"use client";

import { useEffect, useState } from "react";
import { useRouter, usePathname } from "next/navigation";
import Link from "next/link";
import { fetchMe, logout, type Me } from "@/lib/auth";
import { fetchChannels, createChannel, type Channel } from "@/lib/channels";
import { getCableConsumer } from "@/lib/cable";

type ReadAdvancedEvent = {
  type: "read.advanced";
  channel_id: number;
  last_read_message_id: number;
};

export default function ChannelsLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const [me, setMe] = useState<Me | null>(null);
  const [channels, setChannels] = useState<Channel[]>([]);
  const [newChannelName, setNewChannelName] = useState("");
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    fetchMe()
      .then((data) => !cancelled && setMe(data))
      .catch(() => router.replace("/login"));
    return () => {
      cancelled = true;
    };
  }, [router]);

  useEffect(() => {
    if (!me) return;
    let cancelled = false;
    fetchChannels()
      .then((data) => !cancelled && setChannels(data))
      .catch((err) => !cancelled && setError(err instanceof Error ? err.message : String(err)));
    return () => {
      cancelled = true;
    };
  }, [me]);

  // ADR 0002: UserChannel 購読で他デバイスの既読 advance を反映
  useEffect(() => {
    if (!me) return;
    const subscription = getCableConsumer().subscriptions.create(
      { channel: "UserChannel" },
      {
        received(data: ReadAdvancedEvent) {
          if (data.type !== "read.advanced") return;
          setChannels((prev) =>
            prev.map((c) =>
              c.id === data.channel_id
                ? { ...c, last_read_message_id: data.last_read_message_id }
                : c,
            ),
          );
        },
      },
    );
    return () => {
      subscription.unsubscribe();
    };
  }, [me]);

  async function handleCreateChannel(e: React.FormEvent) {
    e.preventDefault();
    const name = newChannelName.trim();
    if (!name) return;
    setError(null);
    try {
      const channel = await createChannel(name);
      setChannels((prev) => [...prev, channel]);
      setNewChannelName("");
      router.push(`/channels/${channel.id}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "チャンネル作成に失敗しました");
    }
  }

  async function handleLogout() {
    await logout();
    router.push("/login");
  }

  if (!me) {
    return (
      <div className="flex flex-1 items-center justify-center text-sm text-slate-500">Loading…</div>
    );
  }

  return (
    <div className="flex flex-1">
      <aside className="flex w-64 flex-col bg-slate-900 text-slate-100">
        <header className="border-b border-slate-700 px-4 py-3">
          <p className="text-xs uppercase tracking-wider text-slate-400">Slack-style chat</p>
          <p className="mt-1 text-sm font-medium">{me.display_name}</p>
        </header>

        <nav className="flex-1 overflow-y-auto px-2 py-3">
          <p className="px-2 pb-2 text-xs uppercase tracking-wider text-slate-400">Channels</p>
          <ul className="space-y-1">
            {channels.map((ch) => {
              const active = pathname === `/channels/${ch.id}`;
              const unread =
                ch.latest_message_id != null &&
                ch.latest_message_id > (ch.last_read_message_id ?? 0);
              return (
                <li key={ch.id}>
                  <Link
                    href={`/channels/${ch.id}`}
                    data-channel-id={ch.id}
                    data-unread={unread ? "true" : "false"}
                    className={`flex items-center justify-between rounded px-2 py-1 text-sm ${active ? "bg-slate-700" : "hover:bg-slate-800"}`}
                  >
                    <span className={unread ? "font-semibold" : ""}>
                      # {ch.name}
                    </span>
                    {unread && (
                      <span
                        aria-label="未読あり"
                        className="ml-2 inline-block h-2 w-2 rounded-full bg-indigo-400"
                      />
                    )}
                  </Link>
                </li>
              );
            })}
          </ul>
        </nav>

        <form onSubmit={handleCreateChannel} className="border-t border-slate-700 p-3">
          <label htmlFor="new-channel" className="text-xs uppercase tracking-wider text-slate-400">
            新規チャンネル
          </label>
          <div className="mt-1 flex gap-2">
            <input
              id="new-channel"
              type="text"
              value={newChannelName}
              onChange={(e) => setNewChannelName(e.target.value)}
              placeholder="general"
              className="flex-1 rounded bg-slate-800 px-2 py-1 text-sm focus:outline-none focus:ring-1 focus:ring-indigo-500"
            />
            <button
              type="submit"
              className="rounded bg-indigo-600 px-2 py-1 text-sm hover:bg-indigo-700"
              aria-label="Create channel"
            >
              +
            </button>
          </div>
        </form>

        <div className="border-t border-slate-700 p-3">
          <button
            onClick={handleLogout}
            className="w-full text-left text-sm text-slate-400 hover:text-slate-200"
          >
            ログアウト
          </button>
        </div>
      </aside>

      <main className="flex flex-1 flex-col bg-slate-50 dark:bg-slate-950">
        {error && (
          <div role="alert" className="border-b border-red-200 bg-red-50 px-4 py-2 text-sm text-red-700">
            {error}
          </div>
        )}
        {children}
      </main>
    </div>
  );
}
