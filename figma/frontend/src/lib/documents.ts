import { api } from "./api";

export type DocumentSummary = {
  id: number;
  name: string;
  owner_id: number;
  version: number;
  role: string;
};

export type SnapshotObject = {
  shape_id: string;
  kind: string;
  props: Record<string, number | string | boolean>;
  z_index: number;
  deleted: boolean;
};

export type Snapshot = {
  document: DocumentSummary;
  version: number;
  objects: SnapshotObject[];
};

export async function listDocuments(): Promise<DocumentSummary[]> {
  const res = await api("/documents");
  if (!res.ok) throw new Error("一覧取得に失敗しました");
  return res.json();
}

export async function createDocument(name: string): Promise<DocumentSummary> {
  const res = await api("/documents", { method: "POST", body: JSON.stringify({ name }) });
  if (!res.ok) throw new Error("作成に失敗しました");
  return res.json();
}

export async function fetchSnapshot(id: number): Promise<Snapshot> {
  const res = await api(`/documents/${id}`);
  if (!res.ok) throw new Error("snapshot 取得に失敗しました");
  return res.json();
}
