FactoryBot.define do
  factory :event_type do
    host
    sequence(:slug)  { |n| "event-type-#{n}" }
    title { "30 minute interview" }
    duration_minutes { 30 }
    before_buffer_minutes { 0 }
    after_buffer_minutes { 0 }
    min_notice_minutes { 60 }
    max_advance_days { 60 }
    active { true }
  end
end
