# == Schema Information
#
# Table name: invoices
#
#  id                       :bigint(8)        not null, primary key
#  amount_due               :integer
#  amount_paid              :integer
#  billable_type            :string
#  date                     :datetime
#  description              :string
#  due_date                 :datetime
#  number                   :string
#  refund_amount_in_cents   :integer
#  refunded_at              :datetime
#  status                   :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  billable_id              :bigint(8)
#  location_id              :integer
#  operator_id              :integer
#  stripe_invoice_id        :string
#  stripe_payment_intent_id :string
#
# Indexes
#
#  index_invoices_on_billable_type_and_billable_id  (billable_type,billable_id)
#  index_invoices_on_location_id                    (location_id)
#  index_invoices_on_stripe_payment_intent_id       (stripe_payment_intent_id)
#
FactoryBot.define do
  factory :invoice do
    association :operator
    association :billable, factory: :organization
    association :location
    amount_due { 1000 }
    amount_paid { 0 }
    date { Time.current }
    due_date { 30.days.from_now }
    status { 'open' }
    number { "INV-#{SecureRandom.hex(4)}" }
  end
end
