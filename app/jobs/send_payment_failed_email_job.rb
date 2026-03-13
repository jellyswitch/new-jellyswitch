class SendPaymentFailedEmailJob < ApplicationJob
  queue_as :default

  def perform(stripe_invoice_id, operator_id)
    operator = Operator.find_by(id: operator_id)
    return unless operator

    ActsAsTenant.with_tenant(operator) do
      invoice = Invoice.find_by(stripe_invoice_id: stripe_invoice_id)
      return unless invoice

      # Invoice billable is polymorphic — can be User or Organization
      user = case invoice.billable
             when User
               invoice.billable
             when Organization
               invoice.billable.owner
             else
               nil
             end

      return unless user&.email.present?

      UserMailer.payment_failed_email(user, operator, invoice).deliver_now
    end
  rescue => e
    Honeybadger.notify(e)
    Rails.logger.error("SendPaymentFailedEmailJob failed: #{e.class}: #{e.message}")
  end
end
