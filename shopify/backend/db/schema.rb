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

ActiveRecord::Schema[8.1].define(version: 2026_05_05_100010) do
  create_table "account_login_change_keys", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "deadline", null: false
    t.string "key", null: false
    t.string "login", null: false
  end

  create_table "account_password_reset_keys", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "deadline", null: false
    t.datetime "email_last_sent", default: -> { "CURRENT_TIMESTAMP(6)" }, null: false
    t.string "key", null: false
  end

  create_table "account_remember_keys", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "deadline", null: false
    t.string "key", null: false
  end

  create_table "account_verification_keys", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "email_last_sent", default: -> { "CURRENT_TIMESTAMP(6)" }, null: false
    t.string "key", null: false
    t.datetime "requested_at", default: -> { "CURRENT_TIMESTAMP(6)" }, null: false
  end

  create_table "accounts", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "email", null: false
    t.string "password_hash"
    t.integer "status", default: 1, null: false
    t.index ["email"], name: "index_accounts_on_email", unique: true
  end

  create_table "apps_app_installations", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "api_token_digest", null: false
    t.bigint "app_id", null: false
    t.datetime "created_at", null: false
    t.string "scopes", default: "", null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["api_token_digest"], name: "index_apps_app_installations_on_api_token_digest", unique: true
    t.index ["app_id"], name: "index_apps_app_installations_on_app_id"
    t.index ["shop_id", "app_id"], name: "index_apps_app_installations_on_shop_id_and_app_id", unique: true
    t.index ["shop_id"], name: "index_apps_app_installations_on_shop_id"
  end

  create_table "apps_apps", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "secret", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_apps_apps_on_name", unique: true
  end

  create_table "apps_webhook_deliveries", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.string "delivery_id", null: false
    t.text "last_error"
    t.datetime "next_attempt_at"
    t.text "payload", null: false
    t.bigint "shop_id", null: false
    t.integer "status", default: 0, null: false
    t.bigint "subscription_id", null: false
    t.string "topic", null: false
    t.datetime "updated_at", null: false
    t.index ["delivery_id"], name: "index_apps_webhook_deliveries_on_delivery_id", unique: true
    t.index ["shop_id"], name: "index_apps_webhook_deliveries_on_shop_id"
    t.index ["status", "next_attempt_at"], name: "index_apps_webhook_deliveries_on_status_and_next_attempt_at"
    t.index ["subscription_id"], name: "index_apps_webhook_deliveries_on_subscription_id"
  end

  create_table "apps_webhook_subscriptions", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "app_installation_id", null: false
    t.datetime "created_at", null: false
    t.string "endpoint", null: false
    t.bigint "shop_id", null: false
    t.string "topic", null: false
    t.datetime "updated_at", null: false
    t.index ["app_installation_id"], name: "index_apps_webhook_subscriptions_on_app_installation_id"
    t.index ["shop_id", "topic"], name: "index_apps_webhook_subscriptions_on_shop_id_and_topic"
    t.index ["shop_id"], name: "index_apps_webhook_subscriptions_on_shop_id"
  end

  create_table "catalog_products", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "shop_id", null: false
    t.string "slug", null: false
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "slug"], name: "index_catalog_products_on_shop_id_and_slug", unique: true
    t.index ["shop_id"], name: "index_catalog_products_on_shop_id"
  end

  create_table "catalog_variants", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "JPY", null: false
    t.integer "price_cents", default: 0, null: false
    t.bigint "product_id", null: false
    t.bigint "shop_id", null: false
    t.string "sku", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_catalog_variants_on_product_id"
    t.index ["shop_id", "sku"], name: "index_catalog_variants_on_shop_id_and_sku", unique: true
    t.index ["shop_id"], name: "index_catalog_variants_on_shop_id"
  end

  create_table "core_shops", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "next_order_number", default: 1, null: false
    t.string "subdomain", null: false
    t.datetime "updated_at", null: false
    t.index ["subdomain"], name: "index_core_shops_on_subdomain", unique: true
  end

  create_table "core_users", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "email"], name: "index_core_users_on_shop_id_and_email", unique: true
    t.index ["shop_id"], name: "index_core_users_on_shop_id"
  end

  create_table "inventory_levels", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "location_id", null: false
    t.integer "on_hand", default: 0, null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "variant_id", null: false
    t.index ["location_id"], name: "index_inventory_levels_on_location_id"
    t.index ["shop_id"], name: "index_inventory_levels_on_shop_id"
    t.index ["variant_id", "location_id"], name: "index_inventory_levels_on_variant_id_and_location_id", unique: true
    t.index ["variant_id"], name: "index_inventory_levels_on_variant_id"
  end

  create_table "inventory_locations", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", default: "warehouse", null: false
    t.string "name", null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.index ["shop_id", "name"], name: "index_inventory_locations_on_shop_id_and_name", unique: true
    t.index ["shop_id"], name: "index_inventory_locations_on_shop_id"
  end

  create_table "inventory_stock_movements", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP(6)" }, null: false
    t.integer "delta", null: false
    t.bigint "location_id", null: false
    t.string "reason", null: false
    t.bigint "shop_id", null: false
    t.bigint "source_id"
    t.string "source_type"
    t.bigint "variant_id", null: false
    t.index ["location_id"], name: "index_inventory_stock_movements_on_location_id"
    t.index ["shop_id"], name: "index_inventory_stock_movements_on_shop_id"
    t.index ["source_type", "source_id"], name: "index_inventory_stock_movements_on_source_type_and_source_id"
    t.index ["variant_id", "location_id", "created_at"], name: "idx_stock_movements_lookup"
    t.index ["variant_id"], name: "index_inventory_stock_movements_on_variant_id"
  end

  create_table "orders_cart_items", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "cart_id", null: false
    t.datetime "created_at", null: false
    t.integer "quantity", default: 1, null: false
    t.bigint "shop_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "variant_id", null: false
    t.index ["cart_id", "variant_id"], name: "index_orders_cart_items_on_cart_id_and_variant_id", unique: true
    t.index ["cart_id"], name: "index_orders_cart_items_on_cart_id"
    t.index ["shop_id"], name: "index_orders_cart_items_on_shop_id"
    t.index ["variant_id"], name: "index_orders_cart_items_on_variant_id"
  end

  create_table "orders_carts", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.integer "active_marker"
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.bigint "shop_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_orders_carts_on_customer_id"
    t.index ["shop_id", "customer_id", "active_marker"], name: "idx_orders_carts_one_active_per_customer", unique: true
    t.index ["shop_id", "customer_id", "status"], name: "index_orders_carts_on_shop_id_and_customer_id_and_status"
    t.index ["shop_id"], name: "index_orders_carts_on_shop_id"
  end

  create_table "orders_order_items", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, null: false
    t.bigint "order_id", null: false
    t.integer "quantity", null: false
    t.bigint "shop_id", null: false
    t.bigint "unit_price_cents", null: false
    t.datetime "updated_at", null: false
    t.bigint "variant_id", null: false
    t.index ["order_id", "variant_id"], name: "index_orders_order_items_on_order_id_and_variant_id"
    t.index ["order_id"], name: "index_orders_order_items_on_order_id"
    t.index ["shop_id"], name: "index_orders_order_items_on_shop_id"
    t.index ["variant_id"], name: "index_orders_order_items_on_variant_id"
  end

  create_table "orders_orders", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency", limit: 3, default: "JPY", null: false
    t.bigint "customer_id", null: false
    t.bigint "number", null: false
    t.bigint "shop_id", null: false
    t.integer "status", default: 0, null: false
    t.bigint "total_cents", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_orders_orders_on_customer_id"
    t.index ["shop_id", "number"], name: "index_orders_orders_on_shop_id_and_number", unique: true
    t.index ["shop_id", "status", "created_at"], name: "index_orders_orders_on_shop_id_and_status_and_created_at"
    t.index ["shop_id"], name: "index_orders_orders_on_shop_id"
  end

  create_table "solid_queue_blocked_executions", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  add_foreign_key "account_login_change_keys", "accounts", column: "id"
  add_foreign_key "account_password_reset_keys", "accounts", column: "id"
  add_foreign_key "account_remember_keys", "accounts", column: "id"
  add_foreign_key "account_verification_keys", "accounts", column: "id"
  add_foreign_key "apps_app_installations", "apps_apps", column: "app_id"
  add_foreign_key "apps_app_installations", "core_shops", column: "shop_id"
  add_foreign_key "apps_webhook_deliveries", "apps_webhook_subscriptions", column: "subscription_id"
  add_foreign_key "apps_webhook_deliveries", "core_shops", column: "shop_id"
  add_foreign_key "apps_webhook_subscriptions", "apps_app_installations", column: "app_installation_id"
  add_foreign_key "apps_webhook_subscriptions", "core_shops", column: "shop_id"
  add_foreign_key "catalog_products", "core_shops", column: "shop_id"
  add_foreign_key "catalog_variants", "catalog_products", column: "product_id"
  add_foreign_key "catalog_variants", "core_shops", column: "shop_id"
  add_foreign_key "core_users", "core_shops", column: "shop_id"
  add_foreign_key "inventory_levels", "catalog_variants", column: "variant_id"
  add_foreign_key "inventory_levels", "core_shops", column: "shop_id"
  add_foreign_key "inventory_levels", "inventory_locations", column: "location_id"
  add_foreign_key "inventory_locations", "core_shops", column: "shop_id"
  add_foreign_key "inventory_stock_movements", "catalog_variants", column: "variant_id"
  add_foreign_key "inventory_stock_movements", "core_shops", column: "shop_id"
  add_foreign_key "inventory_stock_movements", "inventory_locations", column: "location_id"
  add_foreign_key "orders_cart_items", "catalog_variants", column: "variant_id"
  add_foreign_key "orders_cart_items", "core_shops", column: "shop_id"
  add_foreign_key "orders_cart_items", "orders_carts", column: "cart_id"
  add_foreign_key "orders_carts", "core_shops", column: "shop_id"
  add_foreign_key "orders_carts", "core_users", column: "customer_id"
  add_foreign_key "orders_order_items", "catalog_variants", column: "variant_id"
  add_foreign_key "orders_order_items", "core_shops", column: "shop_id"
  add_foreign_key "orders_order_items", "orders_orders", column: "order_id"
  add_foreign_key "orders_orders", "core_shops", column: "shop_id"
  add_foreign_key "orders_orders", "core_users", column: "customer_id"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
end
