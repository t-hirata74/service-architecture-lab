// ADR 0003: fetch + ReadableStream で SSE を消費する hook.
// EventSource を使わない理由 (ADR 0003 採用理由 / 修正後):
//   - AbortController で明示的に中断できる (queries 切替時にクリーンに止めたい)
//   - Authorization / X-User-Id ヘッダを設定したい (cookie auth 以外も将来扱う)
//   - 失敗時の再接続を自前で制御 (ADR 0001: 失敗即終了 / 自動再接続なし)

import { DEV_USER_ID } from "./api";

export type SseEvent = {
  event: string;
  data: unknown;
};

export type SseHandlers = {
  onEvent: (ev: SseEvent) => void;
  onError?: (err: unknown) => void;
  onClose?: () => void;
};

// Open an SSE stream against `url` and feed parsed events to handlers.
// Returns an AbortController so the caller can cancel.
export function openSseStream(url: string, handlers: SseHandlers): AbortController {
  const ctrl = new AbortController();

  (async () => {
    try {
      const res = await fetch(url, {
        method: "GET",
        headers: {
          Accept: "text/event-stream",
          "X-User-Id": DEV_USER_ID,
        },
        signal: ctrl.signal,
        credentials: "include",
      });

      if (!res.body) {
        handlers.onError?.(new Error("response.body is null (no streaming support)"));
        handlers.onClose?.();
        return;
      }

      const reader = res.body.getReader();
      const decoder = new TextDecoder("utf-8");
      let buffer = "";

      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });

        // SSE event は \n\n 区切り
        let sepIdx;
        while ((sepIdx = buffer.indexOf("\n\n")) !== -1) {
          const block = buffer.slice(0, sepIdx);
          buffer = buffer.slice(sepIdx + 2);
          const ev = parseSseBlock(block);
          if (ev) handlers.onEvent(ev);
        }
      }
      // 末尾 flush
      const tail = buffer.trim();
      if (tail.length > 0) {
        const ev = parseSseBlock(tail);
        if (ev) handlers.onEvent(ev);
      }
    } catch (err) {
      if ((err as { name?: string }).name === "AbortError") return;
      handlers.onError?.(err);
    } finally {
      handlers.onClose?.();
    }
  })();

  return ctrl;
}

function parseSseBlock(block: string): SseEvent | null {
  let event: string | null = null;
  const dataLines: string[] = [];
  for (const raw of block.split("\n")) {
    const line = raw.trimEnd();
    if (line.length === 0) continue;
    if (line.startsWith(":")) continue; // keepalive comment
    if (line.startsWith("event:")) {
      event = line.slice("event:".length).trim();
    } else if (line.startsWith("data:")) {
      dataLines.push(line.slice("data:".length).trim());
    }
  }
  if (dataLines.length === 0) return null;
  try {
    return { event: event ?? "message", data: JSON.parse(dataLines.join("\n")) };
  } catch {
    return null;
  }
}
