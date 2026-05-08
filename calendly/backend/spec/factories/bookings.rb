FactoryBot.define do
  factory :booking do
    event_type
    host { event_type.host }
    start_at { Time.utc(2026, 6, 1, 9, 0) }
    end_at   { start_at + event_type.duration_minutes.minutes }
    sequence(:invitee_email) { |n| "invitee#{n}@example.com" }
    invitee_name { "Invitee" }
    invitee_tz_id { "America/New_York" }
    status { "confirmed" }
  end
end
