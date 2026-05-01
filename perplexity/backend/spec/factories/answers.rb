FactoryBot.define do
  factory :answer do
    query
    body { "東京タワーは 1958 年に完成した [#src_1]。" }
    status { "completed" }
  end
end
