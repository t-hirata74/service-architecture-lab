class CreateCanvasObjects < ActiveRecord::Migration[8.1]
  # LWW 解決済みの現在状態 (materialized / snapshot 用、ADR 0002)。
  # shape_id は client 生成 UUID (offline create 対応 / AR の Object#object_id shadowing を避け object_id にしない)。
  # prop_clocks は per-prop Lamport clock {"x":{"l":12,"a":3}, ...} (ADR 0001)。
  def change
    create_table :canvas_objects do |t|
      t.bigint :document_id, null: false
      t.string :shape_id, null: false
      t.string :kind, null: false                       # rect / ellipse / text
      t.json :props, null: false                        # {"x":..,"y":..,"w":..,"h":..,"fill":..,"text":..}
      t.json :prop_clocks, null: false                  # {"x":{"l":..,"a":..}, ...}
      t.boolean :deleted, null: false, default: false   # props["deleted"] の materialized 写像 (snapshot filter 用)
      t.integer :z_index, null: false, default: 0
      t.bigint :last_seq, null: false, default: 0
      t.timestamps
      t.index [:document_id, :shape_id], unique: true
      t.index [:document_id, :deleted]
    end
    add_foreign_key :canvas_objects, :documents
  end
end
