FactoryBot.define do
  factory :meeting do
    association :host, factory: :user
    sequence(:title) { |n| "Meeting #{n}" }
    status { "scheduled" }
    scheduled_start_at { 1.hour.from_now }
  end
end
