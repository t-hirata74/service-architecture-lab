class Account < ApplicationRecord
  include Rodauth::Rails.model
  enum :status, { unverified: 1, verified: 2, closed: 3 }

  # 1:1 shared primary key (users.id = accounts.id)
  has_one :user, foreign_key: :id, primary_key: :id, dependent: :destroy, inverse_of: :account
end
