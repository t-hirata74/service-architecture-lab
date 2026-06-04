class CreateDocuments < ActiveRecord::Migration[8.1]
  # canvas file。version は per-doc 単調増加カウンタで op の総順序 seq を採番する (ADR 0002)。
  def change
    create_table :documents do |t|
      t.string :name, null: false
      t.bigint :owner_id, null: false
      t.bigint :version, null: false, default: 0
      t.timestamps
      t.index :owner_id
    end
    add_foreign_key :documents, :users, column: :owner_id
  end
end
