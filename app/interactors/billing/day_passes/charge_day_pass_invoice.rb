
class Billing::DayPasses::ChargeDayPassInvoice
  include Interactor

  delegate :day_pass, :location, to: :context

  def call
    return if day_pass.day_pass_type.free?
    return if context.comp
    return if day_pass.billable.out_of_band?
    # Note: previously short-circuited when context.token.present? on the
    # assumption Stripe auto-advance would charge later. That deferred charge
    # left members without a clear confirmation and led to retry loops, so
    # we now charge synchronously via the customer's just-attached card.

    invoice = day_pass.invoice
    return unless invoice

    result = Billing::Invoices::ChargeInvoice.call(
      invoice: invoice,
      operator: location.operator
    )

    unless result.success?
      context.fail!(message: "Payment failed. Please update your payment method and try again.")
    end
  end
end
