FactoryBot.define do
  factory :pull_request do
    repository
    association :author, factory: :user
    sequence(:number) { |n| n + 1000 }
    sequence(:title) { |n| "PR #{n}" }
    body { "" }
    state { :open }
    mergeable_state { :mergeable }
    head_ref { "feature/x" }
    base_ref { "main" }
    sequence(:head_sha) { |n| Digest::SHA1.hexdigest("sha-#{n}") }
  end
end
