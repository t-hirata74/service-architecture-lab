class CreateIssueLabels < ActiveRecord::Migration[8.0]
  def change
    create_table :issue_labels do |t|
      t.references :issue, null: false, foreign_key: true
      t.references :label, null: false, foreign_key: true

      t.timestamps
    end

    add_index :issue_labels, %i[issue_id label_id], unique: true
  end
end
