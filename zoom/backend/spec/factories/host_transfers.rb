FactoryBot.define do
  factory :host_transfer do
    association :meeting
    association :from_user, factory: :user
    association :to_user, factory: :user
    transferred_at { Time.current }
    reason { "voluntary" }
  end
end
