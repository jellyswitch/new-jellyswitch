
# == Schema Information
#
# Table name: invoices
#
#  id                :bigint(8)        not null, primary key
#  amount_due        :integer
#  amount_paid       :integer
#  billable_type     :string
#  date              :datetime
#  due_date          :datetime
#  number            :string
#  status            :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  billable_id       :bigint(8)
#  operator_id       :integer
#  location_id       :integer
#  stripe_invoice_id :string
#
# Indexes
#
#  index_invoices_on_billable_type_and_billable_id  (billable_type,billable_id)
#

class Invoice < ApplicationRecord
  include HasLocation

  belongs_to :operator
  acts_as_tenant :operator

  belongs_to :billable, polymorphic: true
  has_many :checkins
  has_many :refunds

  scope :recent, -> { where('date > ?', Time.now - 30.days) }
  scope :open, -> { where("status = 'open'") }
  scope :due, -> { open.where('due_date >= ?', Time.now) }
  scope :paid, ->{ where(status: "paid") }
  scope :delinquent, -> { open.where('due_date < ?', Time.now) }
  scope :groups, -> { where(billable_type: "Organization") }
  scope :last_month, -> {
    last_month_start = (Time.now.beginning_of_month - 1.day).beginning_of_month.to_time.to_i
    this_month_start = Time.now.beginning_of_month.to_time.to_i

    where("date >= to_timestamp(?) AND date < to_timestamp(?)", last_month_start, this_month_start)
  }
  scope :this_month, -> {
    this_month_start = Time.now.beginning_of_month.to_time.to_i

    where("date >= to_timestamp(?)", this_month_start)
  }
  scope :for_week, -> (week_start, week_end) { where('due_date > ? and due_date <= ?', week_start, week_end) }

  VOIDABLE_STATUSES = %w(open uncollectible)
  STATUSES = (VOIDABLE_STATUSES + %w(void paid refunded)).freeze

  STATUSES.each do |invoice_status|
    define_method("#{invoice_status}?") do
      status == invoice_status
    end
  end

  def stripe_invoice
    if stripe_invoice_id.present? && location.present?
      @stripe_invoice ||= Stripe::Invoice.retrieve(stripe_invoice_id, {
        api_key: location.stripe_secret_key,
        stripe_account: location.stripe_user_id
      })
    else
      nil
    end
  rescue Stripe::InvalidRequestError, Stripe::APIConnectionError
    # Stripe-side invoice was deleted (e.g. drafts cancelled when terminating a
    # subscription) or Stripe is unreachable — return nil so display callers
    # like #description and #pdf_url fall back gracefully instead of 500ing.
    nil
  end

  def pdf_url
    if stripe_invoice_id.present? && !void?
      stripe_invoice&.invoice_pdf
    elsif stripe_payment_intent_id.present?
      # PaymentIntent-backed invoice — surface the Stripe-hosted
      # charge receipt. Safer than generating our own PDF for now.
      stripe_charge_receipt_url
    else
      nil
    end
  rescue
    nil
  end

  def stripe_charge_receipt_url
    return nil unless stripe_payment_intent_id.present? && location.present?
    creds = {
      api_key: location.stripe_secret_key,
      stripe_account: location.stripe_user_id,
    }
    pi = Stripe::PaymentIntent.retrieve(stripe_payment_intent_id, creds)
    charge_id = pi.latest_charge
    return nil unless charge_id
    charge = Stripe::Charge.retrieve(charge_id, creds)
    charge.receipt_url
  rescue
    nil
  end

  def pretty_due_date
    if due_date.nil?
      nil
    else
      due_date.strftime("%m/%d/%Y")
    end
  end

  def pretty_date
    date&.strftime("%m/%d/%Y %-l:%M%P")
  end

  def voidable?
    VOIDABLE_STATUSES.include?(status)
  end

  def refunded?
    refunds.length > 0
  end

  def paid?
    status == "paid"
  end

  def payment_method
    # Prefer stored payment intent info (new hold-capture flow), then
    # Stripe invoice billing mode. Never surface "error" — that used to
    # leak to the UI for PI-backed invoices.
    return "Credit Card" if stripe_payment_intent_id.present?
    if stripe_invoice
      stripe_invoice.billing == "charge_automatically" ? "Credit Card" : "Out of band"
    else
      nil
    end
  rescue
    nil
  end

  def description
    # Read self.description column first (hold-capture invoices store a
    # readable description). Fall back to Stripe invoice lines, then a
    # generic default.
    stored = read_attribute(:description)
    return stored if stored.present?
    lines = stripe_invoice&.lines&.data&.map(&:description)&.join("\n")
    return lines if lines.present?
    number.present? ? "Invoice ##{number}" : "Invoice ##{id}"
  rescue
    number.present? ? "Invoice ##{number}" : "Invoice ##{id}"
  end
end
