class CreateDocumentMembers < ActiveRecord::Migration[8.1]
  # document 単位の権限 (owner / editor / viewer)。viewer は op 拒否 (ADR 0004)。
  def change
    create_table :document_members do |t|
      t.bigint :document_id, null: false
      t.bigint :user_id, null: false
      t.string :role, null: false, default: "editor"
      t.timestamps
      t.index [ :document_id, :user_id ], unique: true
      t.index :user_id
    end
    add_foreign_key :document_members, :documents
    add_foreign_key :document_members, :users
  end
end
