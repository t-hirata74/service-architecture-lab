import { describe, expect, it } from 'vitest';
import { MutationRequestSchema } from './mutations';

const base = {
  clientMutationId: '550e8400-e29b-41d4-a716-446655440000',
  workspaceId: 1,
};

describe('MutationRequestSchema', () => {
  it('createIssue の最小形を受理する', () => {
    const r = MutationRequestSchema.safeParse({
      ...base,
      command: { type: 'createIssue', teamId: 1, title: 'Fix login bug' },
    });
    expect(r.success).toBe(true);
  });

  it('未知の type は拒否する (discriminated union)', () => {
    const r = MutationRequestSchema.safeParse({
      ...base,
      command: { type: 'dropTables', teamId: 1 },
    });
    expect(r.success).toBe(false);
  });

  it('clientMutationId が UUID でなければ拒否する', () => {
    const r = MutationRequestSchema.safeParse({
      clientMutationId: 'not-a-uuid',
      workspaceId: 1,
      command: { type: 'deleteIssue', issueId: 1 },
    });
    expect(r.success).toBe(false);
  });

  it('updateIssue の空 patch は拒否する', () => {
    const r = MutationRequestSchema.safeParse({
      ...base,
      command: { type: 'updateIssue', issueId: 1, patch: {} },
    });
    expect(r.success).toBe(false);
  });

  it('moveIssue の sortOrder は末尾 "0" を拒否する', () => {
    const r = MutationRequestSchema.safeParse({
      ...base,
      command: { type: 'moveIssue', issueId: 1, stateId: 2, sortOrder: 'V0' },
    });
    expect(r.success).toBe(false);
  });

  it('createTeam の key は大文字英数のみ', () => {
    const ok = MutationRequestSchema.safeParse({
      ...base,
      command: { type: 'createTeam', key: 'ENG', name: 'Engineering' },
    });
    expect(ok.success).toBe(true);
    const ng = MutationRequestSchema.safeParse({
      ...base,
      command: { type: 'createTeam', key: 'eng', name: 'Engineering' },
    });
    expect(ng.success).toBe(false);
  });
});
