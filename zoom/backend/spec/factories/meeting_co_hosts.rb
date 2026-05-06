FactoryBot.define do
  factory :meeting_co_host do
    association :meeting
    association :user
    association :granted_by_user, factory: :user
    granted_at { Time.current }
  end
end
