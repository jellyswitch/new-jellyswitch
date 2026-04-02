
class Billing::DayPasses::ChargeDayPassInvoice
  include Interactor

  delegate :day_pass, :location, to: :context

  def call
    return if day_pass.day_pass_type.free?
    return if day_pass.billable.out_of_band?

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
