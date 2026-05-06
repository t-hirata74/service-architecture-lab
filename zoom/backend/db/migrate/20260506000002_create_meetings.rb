# ADR 0001: meetings.status を ENUM 永続化、host_id NOT NULL で「最大 1 ホスト」を物理保証 (ADR 0002)
class CreateMeetings < ActiveRecord::Migration[8.1]
  def change
    create_table :meetings do |t|
      t.references :host, null: false, foreign_key: { to_table: :users }
      t.string :title, null: false
      # ENUM 文字列。Rails 側で `enum status: { ... }` を宣言、不正値は DB 制約で弾かない (rails 8 で
      # MySQL の ENUM 型は扱いづらいため string + アプリ層 enum で吸収する方針)。
      t.string :status, null: false, default: "scheduled"
      t.datetime :scheduled_start_at, null: false
      t.datetime :started_at
      t.datetime :ended_at
      t.timestamps
    end

    add_index :meetings, :status
    add_index :meetings, :scheduled_start_at
  end
end
