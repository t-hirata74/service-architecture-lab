class User < ApplicationRecord
  has_many :queries, dependent: :destroy

  validates :email, presence: true, uniqueness: { case_sensitive: false }
end
