# == Schema Information
#
# Table name: invoices
#
#  id                :bigint(8)        not null, primary key
#  amount_due        :integer
#  amount_paid       :integer
#  date              :datetime
#  due_date          :datetime
#  number            :string
#  status            :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  operator_id       :integer
#  stripe_invoice_id :string
#  user_id           :integer
#

FactoryBot.define do
  factory :invoice do

  end
end
