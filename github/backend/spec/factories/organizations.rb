FactoryBot.define do
  factory :organization do
    sequence(:login) { |n| "org#{n}" }
    name { login.titleize }
  end
end
