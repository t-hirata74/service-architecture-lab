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
      <div className="flex flex-1 items-center justify-center text-sm text-[var(--fg-muted)]">
        Loading…
      </div>
    );
  }

  return (
    <div className="flex flex-1">
      <aside
        className="flex w-64 flex-col text-[var(--sidebar-fg)]"
        style={{ background: "var(--sidebar-bg)" }}
      >
        <header className="border-b border-white/10 px-4 py-4">
          <div className="flex items-center gap-2 mb-2">
            <span
              aria-hidden
              className="size-7 rounded-md bg-[var(--accent)] grid place-items-center text-[var(--accent-fg)] text-sm font-bold"
            >
              S
            </span>
            <p className="text-xs uppercase tracking-wider text-[var(--sidebar-fg-muted)]">
              Slack-style
            </p>
          </div>
          <p className="text-sm font-semibold truncate">{me.display_name}</p>
        </header>

        <nav className="flex-1 overflow-y-auto px-2 py-3">
          <p className="px-2 pb-1.5 text-xs uppercase tracking-wider text-[var(--sidebar-fg-muted)]">
            Channels
          </p>
          <ul className="space-y-0.5">
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
                    className={`flex items-center justify-between rounded-md px-2 py-1.5 text-sm transition-colors ${
                      active
                        ? "bg-white/10 text-white"
                        : "text-[var(--sidebar-fg-muted)] hover:bg-white/5 hover:text-white"
                    }`}
                  >
                    <span className={unread ? "font-semibold text-white" : ""}>
                      {`# ${ch.name}`}
                    </span>
                    {unread && (
                      <span
                        aria-label="未読あり"
                        className="ml-2 inline-block size-2 rounded-full bg-[var(--accent)]"
                      />
                    )}
                  </Link>
                </li>
              );
            })}
          </ul>
        </nav>

        <form onSubmit={handleCreateChannel} className="border-t border-white/10 p-3">
          <label
            htmlFor="new-channel"
            className="text-xs uppercase tracking-wider text-[var(--sidebar-fg-muted)]"
          >
            新規チャンネル
          </label>
          <div className="mt-1.5 flex gap-1.5">
            <input
              id="new-channel"
              type="text"
              value={newChannelName}
              onChange={(e) => setNewChannelName(e.target.value)}
              placeholder="general"
              className="flex-1 rounded-md bg-white/10 border border-transparent px-2 h-8 text-sm placeholder:text-[var(--sidebar-fg-muted)]/60 focus:outline-none focus:ring-2 focus:ring-[var(--accent)] focus:border-[var(--accent)] transition-colors"
            />
            <button
              type="submit"
              className="rounded-md bg-[var(--accent)] px-2.5 h-8 text-sm font-medium text-[var(--accent-fg)] hover:bg-[var(--accent-hover)] transition-colors"
              aria-label="Create channel"
            >
              +
            </button>
          </div>
        </form>

        <div className="border-t border-white/10 p-3">
          <button
            onClick={handleLogout}
            className="w-full text-left text-sm text-[var(--sidebar-fg-muted)] hover:text-white transition-colors"
          >
            ログアウト
          </button>
        </div>
      </aside>

      <main className="flex flex-1 flex-col bg-[var(--bg)]">
        {error && (
          <div
            role="alert"
            className="border-b border-rose-200 bg-rose-50 px-4 py-2 text-sm text-rose-700"
          >
            {error}
          </div>
        )}
        {children}
      </main>
    </div>
  );
}
