FactoryBot.define do
  factory :query do
    user
    text { "東京タワーはいつ完成した？" }
    status { "pending" }
  end
end
