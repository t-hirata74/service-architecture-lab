FactoryBot.define do
  # 認証 (Account / rodauth) を介さず User を直接作る。OperationApplier / モデルの
  # unit / convergence spec は actor の id (LWW tie-break) だけ要るため shared PK は気にしない。
  factory :user do
    sequence(:name) { |n| "user#{n}" }
    sequence(:email) { |n| "user#{n}@example.com" }
  end
end
