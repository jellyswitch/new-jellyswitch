class Billing::Leasing::ChargeDeposit
  include Interactor

  delegate :office_lease, :operator, to: :context

  def call
    return unless office_lease.deposit_amount_in_cents.to_i > 0

    subscription = office_lease.subscription
    subscribable = subscription.subscribable
    location = office_lease.location

    stripe_customer_id = if subscribable.respond_to?(:stripe_customer_id)
      subscribable.stripe_customer_id
    elsif subscribable.respond_to?(:stripe_customer_id_for_location)
      subscribable.stripe_customer_id_for_location(location)
    end

    return unless stripe_customer_id.present?

    # Create a one-time invoice item for the deposit
    Stripe::InvoiceItem.create(
      {
        customer: stripe_customer_id,
        amount: office_lease.deposit_amount_in_cents,
        currency: "usd",
        description: "Deposit / Setup Fee for #{office_lease.office.name}"
      },
      { stripe_account: location.stripe_user_id }
    )

    # Create and finalize the invoice immediately
    stripe_invoice = Stripe::Invoice.create(
      {
        customer: stripe_customer_id,
        auto_advance: true,
        description: "Deposit for #{office_lease.office.name} lease"
      },
      { stripe_account: location.stripe_user_id }
    )

    Stripe::Invoice.finalize_invoice(
      stripe_invoice.id,
      {},
      { stripe_account: location.stripe_user_id }
    )
  rescue StandardError => e
    Honeybadger.notify(e)
    Rails.logger.error("ChargeDeposit failed: #{e.class}: #{e.message}")
    # Don't fail the lease creation if deposit charge fails
    # Admin can manually invoice later
  end
end
