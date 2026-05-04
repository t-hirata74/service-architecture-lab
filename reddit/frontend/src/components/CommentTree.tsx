"use client";

import { useState } from "react";
import { type ApiComment, createComment, voteComment } from "@/lib/api";
import { VoteButtons } from "./VoteButtons";

type Props = {
  postId: number;
  comments: ApiComment[];
  onChange: () => void;
  authenticated: boolean;
};

export function CommentTree({ postId, comments, onChange, authenticated }: Props) {
  // path 順 = preorder。depth で階層的に offset を付ける。
  return (
    <div className="space-y-2">
      {comments.map((c) => (
        <CommentRow
          key={c.id}
          postId={postId}
          comment={c}
          onChange={onChange}
          authenticated={authenticated}
        />
      ))}
    </div>
  );
}

function CommentRow({
  postId,
  comment,
  onChange,
  authenticated,
}: {
  postId: number;
  comment: ApiComment;
  onChange: () => void;
  authenticated: boolean;
}) {
  const [replyOpen, setReplyOpen] = useState(false);
  const [replyBody, setReplyBody] = useState("");
  const [submitting, setSubmitting] = useState(false);

  const submitReply = async () => {
    if (!replyBody.trim() || submitting) return;
    setSubmitting(true);
    try {
      await createComment(postId, replyBody.trim(), comment.id);
      setReplyBody("");
      setReplyOpen(false);
      onChange();
    } finally {
      setSubmitting(false);
    }
  };

  const indentPx = (comment.depth - 1) * 16;

  return (
    <div
      className="flex gap-2 border-l-2 border-[var(--border)] pl-3 py-1"
      style={{ marginLeft: indentPx }}
    >
      <VoteButtons
        initialScore={comment.score}
        onVote={async (v) => await voteComment(comment.id, v)}
      />
      <div className="flex-1 text-sm">
        {comment.deleted_at ? (
          <p className="italic text-[var(--muted)]">[deleted]</p>
        ) : (
          <p className="whitespace-pre-wrap">{comment.body}</p>
        )}
        <div className="text-xs text-[var(--muted)] mt-1 flex gap-2">
          <span>depth {comment.depth}</span>
          <span>path {comment.path}</span>
          {authenticated && !comment.deleted_at && (
            <button
              type="button"
              onClick={() => setReplyOpen((v) => !v)}
              className="text-[var(--accent)] hover:underline"
            >
              {replyOpen ? "cancel" : "reply"}
            </button>
          )}
        </div>
        {replyOpen && (
          <div className="mt-2">
            <textarea
              value={replyBody}
              onChange={(e) => setReplyBody(e.target.value)}
              className="w-full text-sm p-2 border border-[var(--border)] rounded bg-[var(--panel-2)]"
              rows={3}
              placeholder="reply..."
            />
            <button
              type="button"
              disabled={submitting}
              onClick={submitReply}
              className="mt-1 text-xs px-3 py-1 rounded bg-[var(--accent)] text-white disabled:opacity-50"
            >
              {submitting ? "posting..." : "post reply"}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
