FactoryBot.define do
  factory :chunk do
    source
    sequence(:ord) { |n| n }
    chunker_version { "fixed-length-recursive-v1" }
    body { "デフォルト chunk 本文。" }
    embedding_version { nil }
    embedding { nil }

    trait :embedded do
      embedding_version { "mock-hash-v1" }
      embedding { Array.new(256) { |i| (i % 11) * 0.01 } }
    end
  end
end
