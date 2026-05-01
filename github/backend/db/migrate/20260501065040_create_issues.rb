class CreateIssues < ActiveRecord::Migration[8.0]
  def change
    create_table :issues do |t|
      t.references :repository, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.integer :number, null: false
      t.string :title, null: false
      t.text :body, null: false
      t.integer :state, null: false, default: 0

      t.timestamps
    end

    add_index :issues, %i[repository_id number], unique: true
    add_index :issues, %i[repository_id state]
  end
end
