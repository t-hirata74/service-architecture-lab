FactoryBot.define do
  factory :issue do
    repository
    association :author, factory: :user
    sequence(:number) { |n| n }
    sequence(:title) { |n| "Issue #{n}" }
    body { "" }
    state { :open }
  end
end
