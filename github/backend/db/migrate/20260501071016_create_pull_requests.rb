class CreatePullRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :pull_requests do |t|
      t.references :repository, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.integer :number, null: false
      t.string :title, null: false
      t.text :body, null: false
      t.integer :state, null: false, default: 0
      t.string :head_ref, null: false
      t.string :base_ref, null: false
      t.integer :mergeable_state, null: false, default: 0
      t.string :head_sha, null: false

      t.timestamps
    end

    add_index :pull_requests, %i[repository_id number], unique: true
    add_index :pull_requests, %i[repository_id state]
  end
end
