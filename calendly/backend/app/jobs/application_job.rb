class ApplicationJob < ActiveJob::Base
  # ADR 0002: 状態遷移を含む transaction の途中で job が走り始めるのを防ぐ (orphan 化防止)。
  # zoom と同形 / docs/operating-patterns.md §21 参照。
  self.enqueue_after_transaction_commit = true

  # 行 lock 競合 (ADR 0002 host 行 FOR UPDATE) で deadlock した場合の自動リトライ。
  retry_on ActiveRecord::Deadlocked
end
