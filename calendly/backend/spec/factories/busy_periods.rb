FactoryBot.define do
  factory :busy_period do
    host
    start_at { Time.utc(2026, 6, 1, 0, 0) }
    end_at   { Time.utc(2026, 6, 1, 1, 0) }
    source { "manual" }
  end
end
