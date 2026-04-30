FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@test.example" }
    sequence(:name)  { |n| "User #{n}" }
  end
end
