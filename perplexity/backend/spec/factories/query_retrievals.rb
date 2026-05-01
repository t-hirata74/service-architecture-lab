FactoryBot.define do
  factory :query_retrieval do
    query
    source
    chunk_id { 1 }
    bm25_score { 0.5 }
    cosine_score { 0.3 }
    fused_score { 0.4 }
    sequence(:rank) { |n| n - 1 }
  end
end
