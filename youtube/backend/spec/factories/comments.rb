FactoryBot.define do
  factory :comment do
    user
    video { create(:video, :published) }
    body { "Phase 5 のサンプルコメント" }
  end
end
