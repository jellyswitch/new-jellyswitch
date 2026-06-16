class Billing::DayPassBundles::ChargeBundleInvoice
  include Interactor

  delegate :day_pass_bundle, :location, to: :context

  def call
    return if day_pass_bundle.day_pass_type.free?
    return if day_pass_bundle.billable.out_of_band?

    invoice = day_pass_bundle.invoice
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
