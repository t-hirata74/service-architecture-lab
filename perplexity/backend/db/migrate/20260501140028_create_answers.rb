# Phase 3: query 1 件につき answer 1 件 (再生成は新 query 扱い、ADR 0001 の方針).
# body は MEDIUMTEXT (最大 16MB) — 引用 marker 込み.
class CreateAnswers < ActiveRecord::Migration[8.1]
  def change
    create_table :answers do |t|
      t.references :query, null: false, foreign_key: true, index: { unique: true }
      t.text :body, null: false, size: :medium
      t.string :status, null: false, default: "streaming", limit: 16
      t.timestamps
    end
  end
end
