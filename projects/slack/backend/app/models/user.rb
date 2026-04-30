class User < ApplicationRecord
  # ADR 0004: rodauth の accounts テーブルと 1:1 の共有 PK で紐付く
  belongs_to :account, foreign_key: :id, primary_key: :id, inverse_of: :user

  has_many :memberships, dependent: :destroy
  has_many :channels, through: :memberships
  has_many :messages, dependent: :nullify

  validates :display_name, presence: true, length: { maximum: 50 }
end
