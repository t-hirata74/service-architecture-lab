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

ActiveRecord::Schema[8.1].define(version: 2026_06_03_102715) do
  create_table "accounts", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_hash"
    t.integer "status", default: 1, null: false
    t.index ["email"], name: "index_accounts_on_email", unique: true
  end

  create_table "canvas_objects", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "deleted", default: false, null: false
    t.bigint "document_id", null: false
    t.string "kind", null: false
    t.bigint "last_seq", default: 0, null: false
    t.json "prop_clocks", null: false
    t.json "props", null: false
    t.string "shape_id", null: false
    t.datetime "updated_at", null: false
    t.integer "z_index", default: 0, null: false
    t.index ["document_id", "deleted"], name: "index_canvas_objects_on_document_id_and_deleted"
    t.index ["document_id", "shape_id"], name: "index_canvas_objects_on_document_id_and_shape_id", unique: true
  end

  create_table "document_members", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "document_id", null: false
    t.string "role", default: "editor", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["document_id", "user_id"], name: "index_document_members_on_document_id_and_user_id", unique: true
    t.index ["user_id"], name: "index_document_members_on_user_id"
  end

  create_table "documents", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "owner_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "version", default: 0, null: false
    t.index ["owner_id"], name: "index_documents_on_owner_id"
  end

  create_table "operations", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "actor_id", null: false
    t.datetime "created_at", null: false
    t.bigint "document_id", null: false
    t.bigint "lamport", null: false
    t.string "op_type", null: false
    t.json "payload", null: false
    t.bigint "seq", null: false
    t.string "shape_id", null: false
    t.index ["actor_id"], name: "fk_rails_d1384c8bde"
    t.index ["document_id", "seq"], name: "index_operations_on_document_id_and_seq", unique: true
  end

  create_table "users", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "canvas_objects", "documents"
  add_foreign_key "document_members", "documents"
  add_foreign_key "document_members", "users"
  add_foreign_key "documents", "users", column: "owner_id"
  add_foreign_key "operations", "documents"
  add_foreign_key "operations", "users", column: "actor_id"
end
