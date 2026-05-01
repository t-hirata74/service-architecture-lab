FactoryBot.define do
  factory :repository do
    organization
    sequence(:name) { |n| "repo-#{n}" }
    description { "" }
    visibility { :private_visibility }
  end
end
