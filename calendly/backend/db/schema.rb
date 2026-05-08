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

ActiveRecord::Schema[8.1].define(version: 2026_05_08_054052) do
  create_table "account_login_change_keys", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "deadline", null: false
    t.string "key", null: false
    t.string "login", null: false
  end

  create_table "account_password_reset_keys", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "deadline", null: false
    t.datetime "email_last_sent", default: -> { "CURRENT_TIMESTAMP(6)" }, null: false
    t.string "key", null: false
  end

  create_table "account_remember_keys", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "deadline", null: false
    t.string "key", null: false
  end

  create_table "account_verification_keys", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "email_last_sent", default: -> { "CURRENT_TIMESTAMP(6)" }, null: false
    t.string "key", null: false
    t.datetime "requested_at", default: -> { "CURRENT_TIMESTAMP(6)" }, null: false
  end

  create_table "accounts", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_hash"
    t.integer "status", default: 1, null: false
    t.index ["email"], name: "index_accounts_on_email", unique: true
  end

  create_table "availability_rules", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "effective_from"
    t.date "effective_until"
    t.time "end_time_of_day", null: false
    t.bigint "event_type_id"
    t.bigint "host_id", null: false
    t.string "rrule", null: false
    t.time "start_time_of_day", null: false
    t.string "tz_id", null: false
    t.datetime "updated_at", null: false
    t.index ["event_type_id"], name: "index_availability_rules_on_event_type_id"
    t.index ["host_id", "event_type_id", "effective_from"], name: "index_availability_rules_on_host_event_effective"
    t.index ["host_id"], name: "index_availability_rules_on_host_id"
  end

  create_table "bookings", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "end_at", null: false
    t.bigint "event_type_id", null: false
    t.bigint "host_id", null: false
    t.string "invitee_email", null: false
    t.string "invitee_name"
    t.string "invitee_tz_id", null: false
    t.datetime "start_at", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["event_type_id"], name: "index_bookings_on_event_type_id"
    t.index ["host_id", "start_at", "end_at", "status"], name: "index_bookings_on_host_overlap"
    t.index ["host_id"], name: "index_bookings_on_host_id"
    t.check_constraint "`start_at` < `end_at`", name: "bookings_start_before_end"
    t.check_constraint "`status` in (_utf8mb4'pending',_utf8mb4'confirmed',_utf8mb4'cancelled',_utf8mb4'completed')", name: "bookings_status_enum"
  end

  create_table "busy_periods", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "end_at", null: false
    t.string "external_id"
    t.bigint "host_id", null: false
    t.string "source", default: "manual", null: false
    t.datetime "start_at", null: false
    t.datetime "updated_at", null: false
    t.index ["host_id", "start_at", "end_at"], name: "index_busy_periods_on_host_id_and_start_at_and_end_at"
    t.index ["host_id"], name: "index_busy_periods_on_host_id"
    t.check_constraint "`start_at` < `end_at`", name: "busy_periods_start_before_end"
  end

  create_table "event_types", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "after_buffer_minutes", default: 0, null: false
    t.integer "before_buffer_minutes", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "duration_minutes", null: false
    t.bigint "host_id", null: false
    t.integer "max_advance_days", default: 60, null: false
    t.integer "min_notice_minutes", default: 60, null: false
    t.string "slug", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["host_id", "slug"], name: "index_event_types_on_host_id_and_slug", unique: true
    t.index ["host_id"], name: "index_event_types_on_host_id"
  end

  create_table "hosts", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "default_tz_id", default: "UTC", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_hosts_on_email", unique: true
  end

  add_foreign_key "account_login_change_keys", "accounts", column: "id"
  add_foreign_key "account_password_reset_keys", "accounts", column: "id"
  add_foreign_key "account_remember_keys", "accounts", column: "id"
  add_foreign_key "account_verification_keys", "accounts", column: "id"
  add_foreign_key "availability_rules", "event_types"
  add_foreign_key "availability_rules", "hosts"
  add_foreign_key "bookings", "event_types"
  add_foreign_key "bookings", "hosts"
  add_foreign_key "busy_periods", "hosts"
  add_foreign_key "event_types", "hosts"
end
