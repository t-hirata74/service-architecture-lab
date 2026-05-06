class ApplicationJob < ActiveJob::Base
  # ADR 0001 / 0003: トランザクション commit 後に enqueue。
  # 状態遷移を含む transaction の途中で job が走り始めるのを防ぐ (orphan 化防止)。
  self.enqueue_after_transaction_commit = true

  retry_on ActiveRecord::Deadlocked
end
