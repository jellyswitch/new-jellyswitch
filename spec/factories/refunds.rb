FactoryBot.define do
  factory :refund do
    invoice
    user
    stripe_refund_id
  end
end
