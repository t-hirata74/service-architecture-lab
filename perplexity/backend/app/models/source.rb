class Source < ApplicationRecord
  has_many :chunks, dependent: :destroy
end
