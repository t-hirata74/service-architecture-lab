FactoryBot.define do
  factory :user do
    sequence(:login) { |n| "user#{n}" }
    sequence(:email) { |n| "user#{n}@example.test" }
    name { login.titleize }
  end
end
