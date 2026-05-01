class CreateComments < ActiveRecord::Migration[8.0]
  def change
    create_table :comments do |t|
      t.references :video, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      # parent_id は nil 可 (トップレベルコメント)。1段までのスレッドにする
      t.references :parent, foreign_key: { to_table: :comments }
      t.text :body, null: false

      t.timestamps
    end

    add_index :comments, [:video_id, :created_at]
  end
end
