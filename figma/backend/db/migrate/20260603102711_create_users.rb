class CreateUsers < ActiveRecord::Migration[8.1]
  # accounts(認証) と shared PK: users.id == accounts.id (ADR 0004 / calendly の Host と同形)。
  # ドメイン属性 (cursor ラベル等に使う name) は users 側に持つ。
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.index :email, unique: true
      t.timestamps
    end
  end
end
