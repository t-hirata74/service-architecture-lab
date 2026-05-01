class CreateRepositoryIssueNumbers < ActiveRecord::Migration[8.0]
  def change
    create_table :repository_issue_numbers do |t|
      t.references :repository, null: false, foreign_key: true, index: { unique: true }
      t.integer :last_number, null: false, default: 0

      t.timestamps
    end
  end
end
