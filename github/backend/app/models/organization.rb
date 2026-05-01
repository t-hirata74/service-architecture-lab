class Organization < ApplicationRecord
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :teams, dependent: :destroy
  has_many :repositories, dependent: :destroy

  validates :login, presence: true, uniqueness: true
end
