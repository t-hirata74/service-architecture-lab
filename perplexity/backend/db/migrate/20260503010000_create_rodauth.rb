# ADR 0007: rodauth-rails + JWT bearer.
# slack の同名マイグレーションを参考に、Phase 5 で導入する rodauth の最小テーブルを作る.
# (verify_account / reset_password / login_change / remember は将来用にスキャフォールド済み)
class CreateRodauth < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.integer :status, null: false, default: 1
      t.string :email, null: false
      t.index :email, unique: true
      t.string :password_hash
    end

    create_table :account_password_reset_keys, id: false do |t|
      t.bigint :id, primary_key: true
      t.foreign_key :accounts, column: :id
      t.string :key, null: false
      t.datetime :deadline, null: false
      t.datetime :email_last_sent, null: false, default: -> { "CURRENT_TIMESTAMP(6)" }
    end

    create_table :account_verification_keys, id: false do |t|
      t.bigint :id, primary_key: true
      t.foreign_key :accounts, column: :id
      t.string :key, null: false
      t.datetime :requested_at, null: false, default: -> { "CURRENT_TIMESTAMP(6)" }
      t.datetime :email_last_sent, null: false, default: -> { "CURRENT_TIMESTAMP(6)" }
    end

    create_table :account_login_change_keys, id: false do |t|
      t.bigint :id, primary_key: true
      t.foreign_key :accounts, column: :id
      t.string :key, null: false
      t.string :login, null: false
      t.datetime :deadline, null: false
    end

    create_table :account_remember_keys, id: false do |t|
      t.bigint :id, primary_key: true
      t.foreign_key :accounts, column: :id
      t.string :key, null: false
      t.datetime :deadline, null: false
    end
  end
end
