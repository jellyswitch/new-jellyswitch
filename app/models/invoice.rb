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

  scope :recent, ->() { where('date > ?', Time.now - 30.days) }
  scope :open, ->() { where("status = 'open'") }
  scope :due, -> () { open.where('due_date >= ?', Time.now) }
  scope :delinquent, ->() { due.where('due_date < ?', Time.now) }
  scope :last_month, -> () {
    last_month_start = (Time.now.beginning_of_month - 1.day).beginning_of_month.to_time.to_i
    this_month_start = Time.now.beginning_of_month.to_time.to_i

    where("date >= to_timestamp(?) AND date < to_timestamp(?)", last_month_start, this_month_start)
  }
  scope :this_month, -> () {
    this_month_start = Time.now.beginning_of_month.to_time.to_i

    where("date >= to_timestamp(?)", this_month_start)
  }

  def stripe_invoice
    @stripe_invoice ||= Stripe::Invoice.retrieve(stripe_invoice_id)
  end

  def pdf_url
    stripe_invoice.invoice_pdf
  end

  def pretty_due_date
    if due_date.nil?
      nil
    else
      due_date.strftime("%m/%d/%Y")
    end
  end

  def pretty_date
    date.strftime("%m/%d/%Y")
  end
end
