class Label < ApplicationRecord
  belongs_to :repository
  has_many :issue_labels, dependent: :destroy
  has_many :issues, through: :issue_labels

  validates :name, presence: true, uniqueness: { scope: :repository_id }
end
