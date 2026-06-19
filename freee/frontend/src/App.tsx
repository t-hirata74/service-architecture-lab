import { useEffect, useState } from 'react';
import { makeClient } from './api';

type Account = {
  id: number;
  companyId: number;
  code: string;
  name: string;
  type: string;
};

/**
 * Phase 2 のスタック疎通デモ: company を切り替えると勘定科目一覧が入れ替わる。
 * 同じ backend / 同じ DB を共有しつつ Postgres RLS が他社データを返さないことを目視できる (ADR 0001)。
 */
export function App() {
  const [companyId, setCompanyId] = useState(1);
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    setError(null);
    makeClient(companyId)
      .accounts.$get()
      .then((res) => res.json())
      .then((rows) => {
        if (alive) setAccounts(rows as Account[]);
      })
      .catch((e: unknown) => {
        if (alive) setError(String(e));
      });
    return () => {
      alive = false;
    };
  }, [companyId]);

  return (
    <main style={{ fontFamily: 'system-ui, sans-serif', maxWidth: 640, margin: '2rem auto' }}>
      <h1>freee — 勘定科目 (company {companyId})</h1>
      <p>
        company:{' '}
        {[1, 2].map((id) => (
          <button
            key={id}
            onClick={() => setCompanyId(id)}
            disabled={companyId === id}
            style={{ marginRight: 8 }}
          >
            {id}
          </button>
        ))}
        <small> ← 切り替えると RLS で別テナントのデータに入れ替わる</small>
      </p>
      {error && <p style={{ color: 'crimson' }}>error: {error}</p>}
      <table border={1} cellPadding={6} style={{ borderCollapse: 'collapse' }}>
        <thead>
          <tr>
            <th>code</th>
            <th>name</th>
            <th>type</th>
          </tr>
        </thead>
        <tbody>
          {accounts.map((a) => (
            <tr key={a.id}>
              <td>{a.code}</td>
              <td>{a.name}</td>
              <td>{a.type}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </main>
  );
}
