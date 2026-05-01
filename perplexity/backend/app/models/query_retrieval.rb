class QueryRetrieval < ApplicationRecord
  self.inheritance_column = nil  # type カラムなし
  belongs_to :query
  belongs_to :source
  # chunk は FK にしないので belongs_to なし (rechunk で消えても audit 残す)

  validates :rank, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
