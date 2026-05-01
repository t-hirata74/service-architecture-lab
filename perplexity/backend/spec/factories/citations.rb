FactoryBot.define do
  factory :citation do
    answer
    source
    chunk_id { 1 }
    sequence(:marker) { |n| "src_#{n}" }
    position { 0 }
  end
end
