FactoryBot.define do
  factory :summary do
    association :meeting
    body { "deterministic mock summary." }
    sequence(:input_hash) { |n| "hash-#{n}" }
    generated_at { Time.current }
  end
end
