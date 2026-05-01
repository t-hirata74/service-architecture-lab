FactoryBot.define do
  factory :team do
    organization
    sequence(:slug) { |n| "team-#{n}" }
    name { slug.titleize }
  end
end
