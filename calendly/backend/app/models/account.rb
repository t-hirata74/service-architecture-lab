# Phase 4-3: rodauth の `accounts` テーブル。Host と shared PK で 1:1 紐付く。
# 認証 (password_hash 管理 / JWT 発行) は rodauth に寄せる。
class Account < ApplicationRecord
  include Rodauth::Rails.model
  enum :status, { unverified: 1, verified: 2, closed: 3 }

  has_one :host, foreign_key: :id, primary_key: :id, dependent: :destroy
end
