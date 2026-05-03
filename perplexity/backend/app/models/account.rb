class Account < ApplicationRecord
  has_one :user, foreign_key: :id, primary_key: :id, inverse_of: :account, dependent: :destroy

  enum :status, { unverified: 1, verified: 2, closed: 3 }
end
