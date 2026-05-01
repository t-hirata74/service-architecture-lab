# ADR 0001: retrieve 結果を query 単位で audit 保存。
# 「どの chunk が allowed_source_ids に入って LLM に渡されたか」が
# Phase 4 の引用整合性検証で必要.
#
# chunk_id は FK にしない (rechunk で chunks 再生成しても audit 壊れない).
# source_id は FK (sources は基本残る).
class CreateQueryRetrievals < ActiveRecord::Migration[8.1]
  def change
    create_table :query_retrievals do |t|
      t.references :query, null: false, foreign_key: true
      t.bigint :chunk_id, null: false
      t.references :source, null: false, foreign_key: true
      t.float :bm25_score, null: false, default: 0.0
      t.float :cosine_score, null: false, default: 0.0
      t.float :fused_score, null: false, default: 0.0
      t.integer :rank, null: false  # 0-indexed: hits 配列の順序
      t.datetime :created_at, null: false
    end
    add_index :query_retrievals, %i[query_id rank], unique: true
    add_index :query_retrievals, :chunk_id
  end
end
