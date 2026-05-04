"use client";

import {
  FormEvent,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { useParams } from "next/navigation";
import Link from "next/link";
import { AuthGuard } from "@/components/AuthGuard";
import {
  ApiChannel,
  ApiMessage,
  createChannel,
  createMessage,
  fetchChannels,
  fetchMessages,
  getStoredUser,
  getToken,
  summarizeChannel,
} from "@/lib/api";
import {
  GatewayClient,
  type MessageCreatePayload,
  type PresencePayload,
  type ReadyPayload,
} from "@/lib/gateway";

type ConnState = "connecting" | "open" | "closed";

function GuildPageInner({ guildId }: { guildId: number }) {
  const me = getStoredUser();
  const [channels, setChannels] = useState<ApiChannel[]>([]);
  const [activeChannel, setActiveChannel] = useState<number | null>(null);
  const [messages, setMessages] = useState<ApiMessage[]>([]);
  const [presences, setPresences] = useState<Map<number, string>>(new Map());
  const [connState, setConnState] = useState<ConnState>("connecting");
  const [body, setBody] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [newChannelName, setNewChannelName] = useState("");
  const [summary, setSummary] = useState<string | null>(null);
  const [summarizing, setSummarizing] = useState(false);

  const messagesRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    fetchChannels(guildId)
      .then(({ channels }) => {
        setChannels(channels);
        if (channels.length > 0) setActiveChannel(channels[0].id);
      })
      .catch((e) => setError(e instanceof Error ? e.message : "failed"));
  }, [guildId]);

  useEffect(() => {
    if (!activeChannel) return;
    setMessages([]);
    setSummary(null);
    fetchMessages(activeChannel)
      .then(({ messages }) => {
        // server returns newest-first; flip for display.
        setMessages([...messages].reverse());
      })
      .catch((e) => setError(e instanceof Error ? e.message : "failed"));
  }, [activeChannel]);

  // WebSocket lifecycle: one connection per guild
  useEffect(() => {
    const token = getToken();
    if (!token) return;

    const handlers = {
      onReady: (d: ReadyPayload) => {
        // READY brings the canonical channel list
        setChannels(d.channels.map((c) => ({
          id: c.id,
          guild_id: d.guild.id,
          name: c.name,
          created_at: "",
        })));
      },
      onMessageCreate: (d: MessageCreatePayload) => {
        // Append only when it's the channel we're viewing
        setMessages((prev) =>
          d.channel_id === activeChannelRef.current
            ? [
                ...prev,
                {
                  id: d.id,
                  channel_id: d.channel_id,
                  user_id: d.user_id,
                  body: d.body,
                  author_username: d.author_username,
                  created_at: d.created_at,
                },
              ]
            : prev,
        );
      },
      onPresenceUpdate: (d: PresencePayload) => {
        setPresences((prev) => {
          const next = new Map(prev);
          if (d.status === "online") next.set(d.user_id, d.username);
          else next.delete(d.user_id);
          return next;
        });
      },
      onInvalidSession: (reason: string) => setError(`invalid session: ${reason}`),
      onConnectionState: (s: ConnState) => setConnState(s),
    };

    const client = new GatewayClient(token, guildId, handlers);
    client.connect();
    return () => client.close();
    // We deliberately depend only on guildId — channel switches reuse the same WS.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [guildId]);

  // We need the latest activeChannel inside the WS handler without re-creating it.
  const activeChannelRef = useRef<number | null>(null);
  useEffect(() => {
    activeChannelRef.current = activeChannel;
  }, [activeChannel]);

  // Auto-scroll on new messages
  useEffect(() => {
    if (!messagesRef.current) return;
    messagesRef.current.scrollTop = messagesRef.current.scrollHeight;
  }, [messages]);

  const onSend = useCallback(
    async (e: FormEvent) => {
      e.preventDefault();
      if (!activeChannel || !body.trim()) return;
      try {
        await createMessage(activeChannel, body.trim());
        setBody("");
      } catch (e) {
        setError(e instanceof Error ? e.message : "failed");
      }
    },
    [activeChannel, body],
  );

  const onCreateChannel = useCallback(
    async (e: FormEvent) => {
      e.preventDefault();
      if (!newChannelName.trim()) return;
      try {
        const { channel } = await createChannel(guildId, newChannelName.trim());
        setNewChannelName("");
        setChannels((prev) => [...prev, channel]);
        setActiveChannel(channel.id);
      } catch (e) {
        setError(e instanceof Error ? e.message : "failed");
      }
    },
    [guildId, newChannelName],
  );

  const onSummarize = useCallback(async () => {
    if (!activeChannel) return;
    setSummarizing(true);
    setSummary(null);
    try {
      const r = await summarizeChannel(activeChannel);
      setSummary(
        r.degraded
          ? `(degraded — ai-worker unreachable, ${r.messages_used} msgs)`
          : `${r.summary} (${r.messages_used} msgs)`,
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : "failed");
    } finally {
      setSummarizing(false);
    }
  }, [activeChannel]);

  const presenceList = useMemo(
    () => Array.from(presences.entries()).map(([id, name]) => ({ id, name })),
    [presences],
  );

  return (
    <div className="grid grid-cols-[200px_1fr_200px] gap-4 h-[calc(100vh-100px)]">
      {/* channels sidebar */}
      <aside className="bg-[var(--panel)] rounded-lg p-3 overflow-y-auto">
        <Link href="/" className="text-xs opacity-60 hover:underline">
          ← guilds
        </Link>
        <h3 className="font-semibold mt-2 mb-2">channels</h3>
        <ul className="space-y-1">
          {channels.map((c) => (
            <li key={c.id}>
              <button
                type="button"
                onClick={() => setActiveChannel(c.id)}
                className={`w-full text-left px-2 py-1 rounded text-sm ${
                  activeChannel === c.id
                    ? "bg-[var(--accent)]"
                    : "hover:bg-[var(--panel-2)]"
                }`}
              >
                # {c.name}
              </button>
            </li>
          ))}
        </ul>
        <form onSubmit={onCreateChannel} className="mt-3 space-y-1">
          <input
            value={newChannelName}
            onChange={(e) => setNewChannelName(e.target.value)}
            placeholder="new channel"
            className="w-full bg-[var(--panel-2)] rounded px-2 py-1 text-sm"
          />
          <button className="w-full bg-[var(--panel-2)] hover:bg-black/40 text-xs py-1 rounded">
            + create
          </button>
        </form>
      </aside>

      {/* messages */}
      <section className="bg-[var(--panel)] rounded-lg p-3 flex flex-col">
        <div className="flex items-center gap-2 mb-2 text-sm">
          <span
            className={`inline-block w-2 h-2 rounded-full ${
              connState === "open"
                ? "bg-green-400"
                : connState === "connecting"
                  ? "bg-yellow-400"
                  : "bg-red-400"
            }`}
          />
          <span className="opacity-70">{connState}</span>
          <div className="flex-1" />
          {activeChannel && (
            <button
              type="button"
              onClick={onSummarize}
              disabled={summarizing}
              className="text-xs px-3 py-1 rounded bg-[var(--panel-2)] hover:bg-black/40 disabled:opacity-50"
            >
              {summarizing ? "summarizing…" : "summarize"}
            </button>
          )}
        </div>

        {summary && (
          <div className="text-xs bg-[var(--panel-2)] rounded p-2 mb-2 whitespace-pre-wrap">
            {summary}
          </div>
        )}

        <div
          ref={messagesRef}
          className="flex-1 overflow-y-auto space-y-2 pr-2"
        >
          {messages.map((m) => (
            <div key={m.id} className="text-sm">
              <span className="font-semibold">@{m.author_username}</span>{" "}
              <span className="opacity-50 text-xs">
                {new Date(m.created_at).toLocaleTimeString()}
              </span>
              <div className="whitespace-pre-wrap">{m.body}</div>
            </div>
          ))}
          {messages.length === 0 && (
            <p className="text-sm opacity-50">no messages yet</p>
          )}
        </div>

        {error && <p className="text-sm text-red-400 mt-2">{error}</p>}

        <form onSubmit={onSend} className="mt-2 flex gap-2">
          <input
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder={
              activeChannel ? "message…" : "select or create a channel"
            }
            disabled={!activeChannel}
            className="flex-1 bg-[var(--panel-2)] rounded px-3 py-2 text-sm"
          />
          <button
            disabled={!activeChannel || !body.trim()}
            className="bg-[var(--accent)] rounded px-4 disabled:opacity-50"
          >
            send
          </button>
        </form>
      </section>

      {/* presence */}
      <aside className="bg-[var(--panel)] rounded-lg p-3 overflow-y-auto">
        <h3 className="font-semibold mb-2 text-sm">online</h3>
        {me && (
          <div className="text-xs opacity-70 mb-2">@{me.username} (you)</div>
        )}
        <ul className="space-y-1 text-sm">
          {presenceList
            .filter((p) => p.id !== me?.id)
            .map((p) => (
              <li key={p.id} className="flex items-center gap-2">
                <span className="inline-block w-2 h-2 rounded-full bg-green-400" />
                @{p.name}
              </li>
            ))}
        </ul>
      </aside>
    </div>
  );
}

export default function GuildPage() {
  const params = useParams<{ guildId: string }>();
  const guildId = Number(params.guildId);
  if (!Number.isFinite(guildId)) return null;
  return (
    <AuthGuard>
      <GuildPageInner guildId={guildId} />
    </AuthGuard>
  );
}
