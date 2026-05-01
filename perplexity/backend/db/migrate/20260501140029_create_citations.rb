# ADR 0004: 引用整合性検証通過分のみ insert される。
# - marker: answer.body 内に出現する文字列 (e.g. "src_3")
# - position: answer.body 内の文字オフセット
# - source_id は FK (引用元), chunk_id は audit 用 (rechunk 後も保持したいので FK にしない)
class CreateCitations < ActiveRecord::Migration[8.1]
  def change
    create_table :citations do |t|
      t.references :answer, null: false, foreign_key: true
      t.references :source, null: false, foreign_key: true
      t.bigint :chunk_id, null: false
      t.string :marker, null: false, limit: 64
      t.integer :position, null: false  # answer.body 内の文字オフセット
      t.datetime :created_at, null: false
    end
    add_index :citations, %i[answer_id position]
  end
end
