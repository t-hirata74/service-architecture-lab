FactoryBot.define do
  factory :label do
    repository
    sequence(:name) { |n| "label-#{n}" }
    color { "ff0000" }
  end
end
