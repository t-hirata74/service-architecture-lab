import Link from "next/link";

export default function Home() {
  return (
    <main className="min-h-screen bg-zinc-50 px-6 py-16">
      <div className="mx-auto max-w-3xl">
        <h1 className="text-3xl font-semibold tracking-tight text-zinc-900">calendly-lab</h1>
        <p className="mt-3 text-zinc-600">
          Calendly / Cal.com を参考にした学習用日程調整プラットフォーム。
          本リポ初の Ruby 4 + Rails 8 プロジェクト。
        </p>

        <section className="mt-10 grid gap-4 sm:grid-cols-2">
          <Card href="/signup" title="Host として登録" body="メール + パスワード + 名前 + デフォルト TZ で Account/Host を同時作成 (rodauth-rails JWT)。" />
          <Card href="/login"  title="Host ログイン"   body="既存アカウントでログインして event_type / availability を管理。" />
          <Card href="/dashboard" title="ダッシュボード" body="自分の event_type / availability_rules / 受信予約一覧。要ログイン。" />
          <Card href="/book" title="予約 (invitee)" body="host id + slug を指定して公開予約ページへ遷移。" />
        </section>

        <section className="mt-12 rounded-md border border-zinc-200 bg-white p-6 text-sm leading-6 text-zinc-700">
          <h2 className="text-base font-semibold text-zinc-900">設計 ADR</h2>
          <ul className="mt-2 list-disc pl-5 space-y-1">
            <li>ADR 0001 — availability merge (都度 SQL 集合演算 + 閉開区間 [start, end))</li>
            <li>ADR 0002 — 同時予約レース防止 (MySQL における EXCLUDE 制約代替 / host 行 FOR UPDATE + overlap 検査)</li>
            <li>ADR 0003 — RRULE 展開 + timezone (壁時計 + tz_id 保存 / DST 跨ぎは壁時計連続性)</li>
          </ul>
        </section>
      </div>
    </main>
  );
}

function Card({ href, title, body }: { href: string; title: string; body: string }) {
  return (
    <Link href={href} className="block rounded-md border border-zinc-200 bg-white p-5 transition hover:border-emerald-300 hover:shadow-sm">
      <h3 className="font-semibold text-zinc-900">{title}</h3>
      <p className="mt-1 text-sm text-zinc-600">{body}</p>
    </Link>
  );
}
