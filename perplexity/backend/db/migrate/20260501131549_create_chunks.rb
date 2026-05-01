# ADR 0002 / 0006:
# - body TEXT に FULLTEXT(body) WITH PARSER ngram を張り、BM25 retrieval に使う
# - embedding は float32 × 256 次元の little-endian BLOB (= 1024 byte)
# - chunker_version (ADR 0006) と embedding_version (ADR 0002) の二軸を持ち、
#   それぞれ独立に再計算可能にする
# - UNIQUE (source_id, ord, chunker_version) で chunker 違いの chunk を並列保持
class CreateChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :chunks do |t|
      t.references :source, null: false, foreign_key: true
      t.integer :ord, null: false
      t.string :chunker_version, null: false, limit: 64
      t.text :body, null: false  # MySQL TEXT (最大 64KB) / chunk は 512 文字想定
      t.binary :embedding, limit: 4096  # float32 × 256 = 1024 byte が想定
      t.string :embedding_version, limit: 64
      t.timestamps
    end

    add_index :chunks, %i[source_id ord chunker_version], unique: true,
              name: "idx_chunks_source_ord_chunker"
    add_index :chunks, :embedding_version, name: "idx_chunks_embedding_version"

    # MySQL 8 ngram parser で全文検索 (innodb_ft_min_token_size=2 を my.cnf 推奨だが、
    # ngram parser はデフォルトで n=2 なので最小 2 文字でマッチ可能)
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          ALTER TABLE chunks ADD FULLTEXT INDEX idx_chunks_body_fulltext (body) WITH PARSER ngram
        SQL
      end
      dir.down do
        execute "ALTER TABLE chunks DROP INDEX idx_chunks_body_fulltext"
      end
    end
  end
end
