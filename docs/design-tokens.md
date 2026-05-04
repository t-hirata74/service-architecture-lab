# Design Tokens — 共通スタイル + per-project accent

各プロジェクトの frontend は **共通の design tokens (typography / spacing / radius / shadow / neutral palette)** を共有し、**accent color と base 明暗だけ** を SaaS モチーフに合わせて差し替える方針。

> 目的: 6 プロジェクト並べたときに「同じリポの一族」と一目で分かる統一感を保ちつつ、各 project の identity (Slack=紫 / Reddit=橙 / GitHub=青 …) は残す。

---

## 共通トークン (light theme)

```css
:root {
  /* surface */
  --bg:           #fafafa;       /* page bg */
  --bg-elevated:  #ffffff;       /* cards / panels */
  --bg-subtle:    #f4f4f5;       /* secondary surface, hover row */
  --border:       #e4e4e7;       /* hairlines */
  --border-strong:#d4d4d8;       /* emphasized borders / form */

  /* foreground */
  --fg:           #18181b;       /* primary text */
  --fg-muted:     #52525b;       /* secondary text */
  --fg-subtle:    #a1a1aa;       /* tertiary / placeholder */

  /* radius */
  --radius-sm:    4px;
  --radius:       8px;
  --radius-lg:    12px;

  /* shadow (3 段階、light) */
  --shadow-sm:    0 1px 2px rgba(0, 0, 0, 0.04);
  --shadow:       0 2px 8px rgba(0, 0, 0, 0.06), 0 1px 2px rgba(0, 0, 0, 0.04);
  --shadow-lg:    0 8px 24px rgba(0, 0, 0, 0.08), 0 2px 4px rgba(0, 0, 0, 0.04);

  /* typography */
  --font-sans:    -apple-system, BlinkMacSystemFont, "Inter", "Segoe UI",
                  "Hiragino Kaku Gothic ProN", "Helvetica Neue", Arial, sans-serif;
  --font-mono:    "SF Mono", Menlo, "Cascadia Code", Consolas, monospace;
}
```

## 共通トークン (dark theme — `prefers-color-scheme: dark` または dark project default)

```css
:root[data-theme="dark"], @media (prefers-color-scheme: dark) {
  --bg:           #0a0a0c;
  --bg-elevated:  #18181b;
  --bg-subtle:    #232328;
  --border:       #2a2a30;
  --border-strong:#3f3f46;
  --fg:           #fafafa;
  --fg-muted:     #a1a1aa;
  --fg-subtle:    #71717a;
  --shadow-sm:    0 1px 2px rgba(0, 0, 0, 0.3);
  --shadow:       0 2px 8px rgba(0, 0, 0, 0.4), 0 1px 2px rgba(0, 0, 0, 0.2);
  --shadow-lg:    0 8px 24px rgba(0, 0, 0, 0.5), 0 2px 4px rgba(0, 0, 0, 0.2);
}
```

---

## Per-project accent (SaaS モチーフ)

| Project | Accent | Accent hover | Theme base |
| --- | --- | --- | --- |
| `slack`      | `#611F69` (deep purple) | `#4A154B` | light, sidebar dark |
| `youtube`    | `#FF0033` (YT red)      | `#CC0029` | **dark default** (YT-like) |
| `github`     | `#0969DA` (primer blue) | `#0550AE` | light |
| `perplexity` | `#20A39E` (teal)        | `#178582` | light |
| `instagram`  | `#E1306C` (IG magenta)  | `#C13584` | light |
| `reddit`     | `#FF4500` (orange)      | `#E03D00` | light |
| `discord`    | `#5865F2` (blurple)     | `#4752C4` | **dark default** |

各プロジェクトの `globals.css` で以下を追加:

```css
:root {
  --accent:       <project specific>;
  --accent-hover: <project specific darker>;
  --accent-fg:    #ffffff;       /* 全プロジェクト共通: accent 上の文字色 */
}
```

---

## 規約

### 1. 直接 hex を書かない、トークン経由で参照

```tsx
// NG
<button className="bg-[#FF4500] text-white">

// OK
<button className="bg-[var(--accent)] text-[var(--accent-fg)] hover:bg-[var(--accent-hover)]">
```

### 2. shadow 3 段階を使い分ける

- `--shadow-sm`: 通常のカード境界 (subtle)
- `--shadow`: モーダル / ドロップダウン
- `--shadow-lg`: ヒーロー要素 / 引き上げたいカード

### 3. transition は **150ms ease-out** で統一

```tsx
className="transition-colors duration-150"  // hover / focus
className="transition-all duration-200"      // shadow / transform を含む
```

### 4. focus-visible に accent ring

```tsx
className="focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--accent)] focus-visible:ring-offset-2"
```

### 5. 空状態は **アイコン + メッセージ + (任意) 主要 CTA**

```tsx
<div className="text-center py-12 text-[var(--fg-subtle)]">
  <Icon className="mx-auto mb-3 size-8 opacity-50" />
  <p className="text-sm">no posts yet</p>
  <button className="mt-4 ...">create the first post</button>
</div>
```

最低 padding `py-8`, アイコンを置く。テキストだけにしない。

### 6. 主要 component の form factor

| Component | スタイル |
| --- | --- |
| Card | `bg-[var(--bg-elevated)] border border-[var(--border)] rounded-[var(--radius)] shadow-sm` |
| Button (primary) | `bg-[var(--accent)] text-[var(--accent-fg)] hover:bg-[var(--accent-hover)] px-4 h-9 rounded-md font-medium transition-colors` |
| Button (ghost) | `text-[var(--fg-muted)] hover:bg-[var(--bg-subtle)] hover:text-[var(--fg)] px-3 h-9 rounded-md transition-colors` |
| Input | `bg-[var(--bg-elevated)] border border-[var(--border-strong)] rounded-md px-3 h-9 focus-visible:ring-2 focus-visible:ring-[var(--accent)] focus-visible:border-[var(--accent)]` |
| List row | `px-4 py-3 hover:bg-[var(--bg-subtle)] transition-colors` |
| Heading h1 | `text-2xl font-bold tracking-tight` |
| Heading h2 | `text-lg font-semibold` |
| Body | `text-sm leading-relaxed` |
| Caption | `text-xs text-[var(--fg-muted)]` |

---

## 関連

- [coding-rules/frontend.md](coding-rules/frontend.md) — Next.js / React / Tailwind の規約
- 各プロジェクトの `frontend/src/app/globals.css` — 上記トークンを実装
