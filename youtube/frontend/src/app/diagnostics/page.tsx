import Header from "@/components/Header";
import { apiBaseUrl } from "@/lib/api";

type HealthResponse = {
  status: string;
  service?: string;
  time?: string;
};

async function fetchBackendHealth(): Promise<HealthResponse | null> {
  try {
    const res = await fetch(`${apiBaseUrl()}/health`, { cache: "no-store" });
    if (!res.ok) return null;
    return (await res.json()) as HealthResponse;
  } catch {
    return null;
  }
}

export default async function Diagnostics() {
  const backend = await fetchBackendHealth();
  return (
    <>
      <Header />
      <main className="mx-auto w-full max-w-3xl flex-1 px-6 py-8 text-sm">
        <h1 className="mb-4 text-xl font-semibold">Diagnostics</h1>
        <section className="rounded border border-white/10 px-4 py-3">
          <div>
            backend: {backend ? (
              <span className="text-emerald-400">{backend.status} ({backend.service})</span>
            ) : (
              <span className="text-red-400">unreachable</span>
            )}
          </div>
          <div className="mt-1 opacity-60">API base: {apiBaseUrl()}</div>
        </section>
      </main>
    </>
  );
}
