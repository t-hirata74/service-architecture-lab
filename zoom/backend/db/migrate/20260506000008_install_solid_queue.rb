# Solid Queue を main DB にインストール (single-DB 同居方針 / shopify と同形)。
# rails new が生成した db/queue_schema.rb の内容を migration として実行する。
class InstallSolidQueue < ActiveRecord::Migration[8.1]
  def up
    schema_file = Rails.root.join("db/queue_schema.rb")
    return unless File.exist?(schema_file)
    return if connection.table_exists?(:solid_queue_jobs)

    load schema_file
  end

  def down
    %w[
      solid_queue_recurring_executions
      solid_queue_recurring_tasks
      solid_queue_scheduled_executions
      solid_queue_ready_executions
      solid_queue_failed_executions
      solid_queue_claimed_executions
      solid_queue_blocked_executions
      solid_queue_pauses
      solid_queue_processes
      solid_queue_semaphores
      solid_queue_jobs
    ].each do |t|
      drop_table t if connection.table_exists?(t)
    end
  end
end
