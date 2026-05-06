FactoryBot.define do
  factory :recording do
    association :meeting
    sequence(:mock_blob_path) { |n| "mock://recordings/#{n}.bin" }
    duration_seconds { 1800 }
    finalized_at { Time.current }
  end
end
