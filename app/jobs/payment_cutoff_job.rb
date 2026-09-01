# Steps 2 and 3 of the three-email non-payment drip (see PaymentCutoff).
# Nightly via Heroku Scheduler → rake payment_cutoff:run.
#
# Each pass advances invoices whose previous notice is old enough and whose
# invoice is STILL open: failure notice → cutoff warning after 48h, warning →
# suspension notice after another 48h. The suspension notice row is what
# User#payment_suspended? keys off, so recording it IS the cutoff.
#
# Only individual, auto-charged members advance: org-billed invoices,
# out-of-band (net-30) members, and staff are filtered here — which also means
# no suspension row is ever created for them, so the derived predicate can
# stay simple.
class PaymentCutoffJob < ApplicationJob
  queue_as :default

  def perform
    Operator.find_each do |operator|
      ActsAsTenant.with_tenant(operator) do
        advance(operator, from: PaymentCutoff::FAILED_NOTICE,
                          to: PaymentCutoff::WARNING_NOTICE,
                          min_age: PaymentCutoff::WARNING_AFTER)
        advance(operator, from: PaymentCutoff::WARNING_NOTICE,
                          to: PaymentCutoff::SUSPENSION_NOTICE,
                          min_age: PaymentCutoff::SUSPEND_AFTER)
      end
    end
  end

  private

  def advance(operator, from:, to:, min_age:)
    ProductEmailSend.where(email_type: from, sendable_type: "Invoice")
                    .where(sent_at: ..min_age.ago)
                    .find_each do |prior|
      invoice = Invoice.find_by(id: prior.sendable_id)
      next unless invoice&.status == "open"
      next if invoice.amount_due.to_i <= 0
      # A future due_date means the invoice isn't late yet (net-30 send_invoice
      # billing) — the drip is for auto-charge failures only.
      next if invoice.due_date.present? && invoice.due_date > Time.current
      next if ProductEmailSend.already_sent?(invoice, to)

      user = invoice.billable
      next unless user.is_a?(User)
      next if user.archived? || user.out_of_band? || user.bill_to_organization?
      next if user.superadmin? || user.admin?

      location = invoice.location || Location.find_by(id: user.original_location_id)
      case to
      when PaymentCutoff::WARNING_NOTICE
        UserMailer.payment_cutoff_warning_email(user, operator, invoice, location).deliver_now
      when PaymentCutoff::SUSPENSION_NOTICE
        UserMailer.payment_suspended_email(user, operator, invoice, location).deliver_now
      end
      ProductEmailSend.record_once(sendable: invoice, email_type: to, user: user, operator: operator)
    rescue => e
      Rails.logger.error("PaymentCutoffJob #{to} error for invoice #{prior.sendable_id}: #{e.class}: #{e.message}")
      Honeybadger.notify(e)
    end
  end
end
