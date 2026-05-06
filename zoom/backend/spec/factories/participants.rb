FactoryBot.define do
  factory :participant do
    association :meeting
    association :user
    status { "waiting" }

    trait :live do
      status { "live" }
      joined_at { 1.minute.ago }
    end

    trait :left do
      status { "left" }
      joined_at { 5.minutes.ago }
      left_at { 1.minute.ago }
    end
  end
end
