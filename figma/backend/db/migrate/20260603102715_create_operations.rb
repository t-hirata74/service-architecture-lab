class CreateOperations < ActiveRecord::Migration[8.1]
  # append-only ordered log (ADR 0002)。seq は commit 時の documents.version (server 権威の総順序)。
  # lamport は LWW 判定用の client 論理時計 (ADR 0001)。append-only なので updated_at は持たない。
  def change
    create_table :operations do |t|
      t.bigint :document_id, null: false
      t.bigint :seq, null: false
      t.bigint :actor_id, null: false
      t.string :shape_id, null: false                   # 対象 canvas object の client UUID
      t.string :op_type, null: false                    # create / update / delete
      t.json :payload, null: false                      # 変更プロパティ {prop: value}
      t.bigint :lamport, null: false
      t.datetime :created_at, null: false
      t.index [ :document_id, :seq ], unique: true        # 総順序 + catch-up (?since=seq)
    end
    add_foreign_key :operations, :documents
    add_foreign_key :operations, :users, column: :actor_id
  end
end
