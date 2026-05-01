class CreateCommitChecks < ActiveRecord::Migration[8.0]
  def change
    create_table :commit_checks do |t|
      t.references :repository, null: false, foreign_key: true
      t.string :head_sha, null: false
      t.string :name, null: false
      t.integer :state, null: false, default: 0
      t.datetime :started_at
      t.datetime :completed_at
      t.text :output

      t.timestamps
    end

    # ADR 0004: 同一 (repository, head_sha, name) は最新で upsert
    add_index :commit_checks, %i[repository_id head_sha name], unique: true, name: "idx_commit_checks_uniq"
    add_index :commit_checks, %i[repository_id head_sha]
  end
end
