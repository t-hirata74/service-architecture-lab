FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.test" }
    sequence(:display_name) { |n| "User #{n}" }
  end
end
