class ApplicationJob < ActiveJob::Base
  # ADR 0001: トランザクション内で perform_later されたジョブは
  # コミット成立後まで enqueue を保留する。これにより videos.status 更新と
  # ジョブ enqueue を「同時に成立する／同時に成立しない」関係にできる。
  # (Rails 8.1 でグローバル設定が deprecate されたため、ジョブ親クラスに置く)
  self.enqueue_after_transaction_commit = true

  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
end
