FactoryBot.define do
  factory :document_member do
    document
    user
    role { "editor" }
  end
end
