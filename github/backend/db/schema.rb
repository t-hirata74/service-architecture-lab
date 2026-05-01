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

ActiveRecord::Schema[8.0].define(version: 2026_05_01_071853) do
  create_table "comments", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "commentable_type", null: false
    t.bigint "commentable_id", null: false
    t.bigint "author_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_comments_on_author_id"
    t.index ["commentable_type", "commentable_id", "created_at"], name: "idx_on_commentable_type_commentable_id_created_at_89c6e27600"
  end

  create_table "commit_checks", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "repository_id", null: false
    t.string "head_sha", null: false
    t.string "name", null: false
    t.integer "state", default: 0, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.text "output"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["repository_id", "head_sha", "name"], name: "idx_commit_checks_uniq", unique: true
    t.index ["repository_id", "head_sha"], name: "index_commit_checks_on_repository_id_and_head_sha"
    t.index ["repository_id"], name: "index_commit_checks_on_repository_id"
  end

  create_table "issue_assignees", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "issue_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["issue_id", "user_id"], name: "index_issue_assignees_on_issue_id_and_user_id", unique: true
    t.index ["issue_id"], name: "index_issue_assignees_on_issue_id"
    t.index ["user_id"], name: "index_issue_assignees_on_user_id"
  end

  create_table "issue_labels", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "issue_id", null: false
    t.bigint "label_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["issue_id", "label_id"], name: "index_issue_labels_on_issue_id_and_label_id", unique: true
    t.index ["issue_id"], name: "index_issue_labels_on_issue_id"
    t.index ["label_id"], name: "index_issue_labels_on_label_id"
  end

  create_table "issues", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "repository_id", null: false
    t.bigint "author_id", null: false
    t.integer "number", null: false
    t.string "title", null: false
    t.text "body", null: false
    t.integer "state", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_issues_on_author_id"
    t.index ["repository_id", "number"], name: "index_issues_on_repository_id_and_number", unique: true
    t.index ["repository_id", "state"], name: "index_issues_on_repository_id_and_state"
    t.index ["repository_id"], name: "index_issues_on_repository_id"
  end

  create_table "labels", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "repository_id", null: false
    t.string "name", null: false
    t.string "color", default: "888888", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["repository_id", "name"], name: "index_labels_on_repository_id_and_name", unique: true
    t.index ["repository_id"], name: "index_labels_on_repository_id"
  end

  create_table "memberships", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.bigint "user_id", null: false
    t.integer "role", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "user_id"], name: "index_memberships_on_organization_id_and_user_id", unique: true
    t.index ["organization_id"], name: "index_memberships_on_organization_id"
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "organizations", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "login", null: false
    t.string "name", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["login"], name: "index_organizations_on_login", unique: true
  end

  create_table "pull_requests", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "repository_id", null: false
    t.bigint "author_id", null: false
    t.integer "number", null: false
    t.string "title", null: false
    t.text "body", null: false
    t.integer "state", default: 0, null: false
    t.string "head_ref", null: false
    t.string "base_ref", null: false
    t.integer "mergeable_state", default: 0, null: false
    t.string "head_sha", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_pull_requests_on_author_id"
    t.index ["repository_id", "number"], name: "index_pull_requests_on_repository_id_and_number", unique: true
    t.index ["repository_id", "state"], name: "index_pull_requests_on_repository_id_and_state"
    t.index ["repository_id"], name: "index_pull_requests_on_repository_id"
  end

  create_table "repositories", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "name", null: false
    t.text "description"
    t.integer "visibility", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "name"], name: "index_repositories_on_organization_id_and_name", unique: true
    t.index ["organization_id"], name: "index_repositories_on_organization_id"
  end

  create_table "repository_collaborators", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "repository_id", null: false
    t.bigint "user_id", null: false
    t.integer "role", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["repository_id", "user_id"], name: "index_repository_collaborators_on_repository_id_and_user_id", unique: true
    t.index ["repository_id"], name: "index_repository_collaborators_on_repository_id"
    t.index ["user_id"], name: "index_repository_collaborators_on_user_id"
  end

  create_table "repository_issue_numbers", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "repository_id", null: false
    t.integer "last_number", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["repository_id"], name: "index_repository_issue_numbers_on_repository_id", unique: true
  end

  create_table "requested_reviewers", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "pull_request_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pull_request_id", "user_id"], name: "index_requested_reviewers_on_pull_request_id_and_user_id", unique: true
    t.index ["pull_request_id"], name: "index_requested_reviewers_on_pull_request_id"
    t.index ["user_id"], name: "index_requested_reviewers_on_user_id"
  end

  create_table "reviews", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "pull_request_id", null: false
    t.bigint "reviewer_id", null: false
    t.integer "state", default: 0, null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pull_request_id", "reviewer_id", "created_at"], name: "idx_on_pull_request_id_reviewer_id_created_at_29861f4c89"
    t.index ["pull_request_id"], name: "index_reviews_on_pull_request_id"
    t.index ["reviewer_id"], name: "index_reviews_on_reviewer_id"
  end

  create_table "team_members", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.bigint "user_id", null: false
    t.integer "role", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id", "user_id"], name: "index_team_members_on_team_id_and_user_id", unique: true
    t.index ["team_id"], name: "index_team_members_on_team_id"
    t.index ["user_id"], name: "index_team_members_on_user_id"
  end

  create_table "team_repository_roles", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.bigint "repository_id", null: false
    t.integer "role", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["repository_id"], name: "index_team_repository_roles_on_repository_id"
    t.index ["team_id", "repository_id"], name: "index_team_repository_roles_on_team_id_and_repository_id", unique: true
    t.index ["team_id"], name: "index_team_repository_roles_on_team_id"
  end

  create_table "teams", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "organization_id", null: false
    t.string "slug", null: false
    t.string "name", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "slug"], name: "index_teams_on_organization_id_and_slug", unique: true
    t.index ["organization_id"], name: "index_teams_on_organization_id"
  end

  create_table "users", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "login", null: false
    t.string "name", default: "", null: false
    t.string "email", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["login"], name: "index_users_on_login", unique: true
  end

  add_foreign_key "comments", "users", column: "author_id"
  add_foreign_key "commit_checks", "repositories"
  add_foreign_key "issue_assignees", "issues"
  add_foreign_key "issue_assignees", "users"
  add_foreign_key "issue_labels", "issues"
  add_foreign_key "issue_labels", "labels"
  add_foreign_key "issues", "repositories"
  add_foreign_key "issues", "users", column: "author_id"
  add_foreign_key "labels", "repositories"
  add_foreign_key "memberships", "organizations"
  add_foreign_key "memberships", "users"
  add_foreign_key "pull_requests", "repositories"
  add_foreign_key "pull_requests", "users", column: "author_id"
  add_foreign_key "repositories", "organizations"
  add_foreign_key "repository_collaborators", "repositories"
  add_foreign_key "repository_collaborators", "users"
  add_foreign_key "repository_issue_numbers", "repositories"
  add_foreign_key "requested_reviewers", "pull_requests"
  add_foreign_key "requested_reviewers", "users"
  add_foreign_key "reviews", "pull_requests"
  add_foreign_key "reviews", "users", column: "reviewer_id"
  add_foreign_key "team_members", "teams"
  add_foreign_key "team_members", "users"
  add_foreign_key "team_repository_roles", "repositories"
  add_foreign_key "team_repository_roles", "teams"
  add_foreign_key "teams", "organizations"
end
