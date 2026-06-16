FactoryBot.define do
  factory :day_pass_bundle do
    association :user
    association :day_pass_type
    operator { user.operator }
    billable { user }
    quantity_purchased { 5 }
    passes_remaining { 5 }
    purchased_at { Time.current }
  end
end
