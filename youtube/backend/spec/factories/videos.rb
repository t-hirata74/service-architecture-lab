FactoryBot.define do
  factory :video do
    user
    sequence(:title) { |n| "Video #{n}" }
    description { "sample description" }
    status { :uploaded }

    trait :transcoding do
      status { :transcoding }
    end

    trait :ready do
      status { :ready }
      duration_seconds { 60 }
    end

    trait :published do
      status { :published }
      duration_seconds { 90 }
      published_at { 1.hour.ago }
    end

    trait :failed do
      status { :failed }
    end

    trait :with_attached_original do
      after(:build) do |video|
        video.original.attach(
          io: StringIO.new("fake-bytes"),
          filename: "sample.mp4",
          content_type: "video/mp4"
        )
      end
    end
  end
end
