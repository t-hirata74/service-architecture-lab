class CreateRodauth < ActiveRecord::Migration[8.1]
  # JWT bearer + JSON のみを使う最小構成 (ADR 0004 / calendly と同形)。
  # verify_account / reset_password / remember は無効化するので付随テーブルは作らない。
  # JWT はステートレスなので account_jwt_refresh_keys 等も持たない (MVP は短命 access token のみ)。
  def change
    create_table :accounts do |t|
      t.integer :status, null: false, default: 1
      t.string :email, null: false
      t.index :email, unique: true
      t.string :password_hash
    end
  end
end
