FactoryBot.define do
  factory :source do
    sequence(:title) { |n| "Source #{n}" }
    sequence(:url)   { |n| "https://example.local/source-#{n}" }
    body { "デフォルト本文。Phase 2 のテストで使う short ドキュメント。" }
  end
end
