class User < ApplicationRecord
  # ADR 0007: rodauth の accounts テーブルと共有 PK で 1:1 紐付く.
  # 既存 (Phase 1-4) の User.email カラムは互換のために残し、create_account 時に同期する.
  belongs_to :account, foreign_key: :id, primary_key: :id, inverse_of: :user, optional: true

  has_many :queries, dependent: :destroy

  validates :email, presence: true, uniqueness: { case_sensitive: false }
end
