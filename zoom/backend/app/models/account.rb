# Phase 4-3: rodauth の `accounts` テーブル。User と shared PK で 1:1 紐付く。
# 認証 (password_hash 管理 / JWT 発行) は rodauth に寄せる。
class Account < ApplicationRecord
  has_one :user, foreign_key: :id, primary_key: :id, dependent: :destroy

  enum :status, { unverified: 1, verified: 2, closed: 3 }
end
