FactoryBot.define do
  factory :host do
    sequence(:email) { |n| "host#{n}@example.com" }
    sequence(:name)  { |n| "Host #{n}" }
    default_tz_id { "Asia/Tokyo" }
  end
end
