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

class Invoice < ApplicationRecord
  belongs_to :operator
  belongs_to :user

  def stripe_invoice
    @stripe_invoice ||= Stripe::Invoice.retrieve(stripe_invoice_id)
  end

  def pdf_url
    stripe_invoice.invoice_pdf
  end
end
