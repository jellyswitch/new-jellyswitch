
class Billing::Reservations::ChargeReservationInvoice
  include Interactor

  delegate :reservation, :invoice, to: :context

  def call
    return unless invoice
    return if reservation.user.out_of_band?
    return if context.token.present?  # New card just added — Stripe auto-charges

    local_invoice = Invoice.find_by(stripe_invoice_id: invoice.id)
    return unless local_invoice

    result = Billing::Invoices::ChargeInvoice.call(
      invoice: local_invoice,
      operator: reservation.room.location.operator
    )

    unless result.success?
      context.fail!(message: "Payment failed. Please update your payment method and try again.")
    end
  end
end
