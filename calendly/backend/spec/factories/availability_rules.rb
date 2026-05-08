FactoryBot.define do
  factory :availability_rule do
    host
    event_type { nil }  # null = host グローバル
    rrule { "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR" }
    start_time_of_day { "09:00:00" }
    end_time_of_day   { "17:00:00" }
    tz_id { "Asia/Tokyo" }
    effective_from { nil }
    effective_until { nil }
  end
end
