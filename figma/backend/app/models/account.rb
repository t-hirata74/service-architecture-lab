class Account < ApplicationRecord
  include Rodauth::Rails.model
  enum :status, { unverified: 1, verified: 2, closed: 3 }

  # shared PK: users.id == accounts.id (ADR 0004 / rodauth_main の after_create_account)。
  has_one :user, primary_key: :id, foreign_key: :id, dependent: :destroy, inverse_of: false
end
