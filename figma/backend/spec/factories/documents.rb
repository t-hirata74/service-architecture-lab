FactoryBot.define do
  factory :document do
    sequence(:name) { |n| "doc#{n}" }
    association :owner, factory: :user

    # owner を member(owner role)としても登録したい場合に使う trait。
    trait :with_owner_member do
      after(:create) do |doc|
        create(:document_member, document: doc, user: doc.owner, role: "owner")
      end
    end
  end
end
