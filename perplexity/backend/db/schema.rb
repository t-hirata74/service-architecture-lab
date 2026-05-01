# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_01_140029) do
  create_table "answers", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.text "body", size: :medium, null: false
    t.datetime "created_at", null: false
    t.bigint "query_id", null: false
    t.string "status", limit: 16, default: "streaming", null: false
    t.datetime "updated_at", null: false
    t.index ["query_id"], name: "index_answers_on_query_id", unique: true
  end

  create_table "chunks", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.text "body", null: false
    t.string "chunker_version", limit: 64, null: false
    t.datetime "created_at", null: false
    t.binary "embedding"
    t.string "embedding_version", limit: 64
    t.integer "ord", null: false
    t.bigint "source_id", null: false
    t.datetime "updated_at", null: false
    t.index ["body"], name: "idx_chunks_body_fulltext", type: :fulltext
    t.index ["embedding_version"], name: "idx_chunks_embedding_version"
    t.index ["source_id", "ord", "chunker_version"], name: "idx_chunks_source_ord_chunker", unique: true
    t.index ["source_id"], name: "index_chunks_on_source_id"
  end

  create_table "citations", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "answer_id", null: false
    t.bigint "chunk_id", null: false
    t.datetime "created_at", null: false
    t.string "marker", limit: 64, null: false
    t.integer "position", null: false
    t.bigint "source_id", null: false
    t.index ["answer_id", "position"], name: "index_citations_on_answer_id_and_position"
    t.index ["answer_id"], name: "index_citations_on_answer_id"
    t.index ["source_id"], name: "index_citations_on_source_id"
  end

  create_table "queries", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "status", limit: 16, default: "pending", null: false
    t.text "text", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "created_at"], name: "index_queries_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_queries_on_user_id"
  end

  create_table "query_retrievals", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.float "bm25_score", default: 0.0, null: false
    t.bigint "chunk_id", null: false
    t.float "cosine_score", default: 0.0, null: false
    t.datetime "created_at", null: false
    t.float "fused_score", default: 0.0, null: false
    t.bigint "query_id", null: false
    t.integer "rank", null: false
    t.bigint "source_id", null: false
    t.index ["chunk_id"], name: "index_query_retrievals_on_chunk_id"
    t.index ["query_id", "rank"], name: "index_query_retrievals_on_query_id_and_rank", unique: true
    t.index ["query_id"], name: "index_query_retrievals_on_query_id"
    t.index ["source_id"], name: "index_query_retrievals_on_source_id"
  end

  create_table "sources", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.text "body", size: :long, null: false
    t.datetime "created_at", null: false
    t.string "title", limit: 500, null: false
    t.datetime "updated_at", null: false
    t.string "url", limit: 1000
  end

  create_table "users", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", limit: 320, null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "answers", "queries"
  add_foreign_key "chunks", "sources"
  add_foreign_key "citations", "answers"
  add_foreign_key "citations", "sources"
  add_foreign_key "queries", "users"
  add_foreign_key "query_retrievals", "queries"
  add_foreign_key "query_retrievals", "sources"
end
