class CreateComments < ActiveRecord::Migration[8.0]
  def change
    create_table :comments do |t|
      t.string :commentable_type, null: false
      t.bigint :commentable_id, null: false
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false

      t.timestamps
    end

    add_index :comments, %i[commentable_type commentable_id created_at]
  end
end
