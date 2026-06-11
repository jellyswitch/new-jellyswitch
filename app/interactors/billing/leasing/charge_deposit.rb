class Billing::Leasing::ChargeDeposit
  include Interactor

  delegate :office_lease, :operator, to: :context

  def call
    return unless office_lease.deposit_amount_in_cents.to_i > 0
    return if office_lease.deposit_invoiced_at.present? # idempotent — already done

    subscription = office_lease.subscription
    location = office_lease.location

    # Use the SAME customer the subscription bills (location-scoped), not the
    # plain stripe_customer_id column — that column is often nil for a brand-new
    # individual lessee, which silently skipped the deposit. See ADR-less note /
    # the lease "Generate deposit invoice" recovery action.
    payer = subscription.billable || subscription.subscribable
    stripe_customer_id = if payer.respond_to?(:stripe_customer_id_for_location)
      payer.stripe_customer_id_for_location(location)
    elsif payer.respond_to?(:stripe_customer_id)
      payer.stripe_customer_id
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
      { api_key: location.stripe_secret_key, stripe_account: location.stripe_user_id }
    )

    # Create and finalize the invoice immediately
    stripe_invoice = Stripe::Invoice.create(
      {
        customer: stripe_customer_id,
        auto_advance: true,
        description: "Deposit for #{office_lease.office.name} lease"
      },
      { api_key: location.stripe_secret_key, stripe_account: location.stripe_user_id }
    )

    Stripe::Invoice.finalize_invoice(
      stripe_invoice.id,
      {},
      { api_key: location.stripe_secret_key, stripe_account: location.stripe_user_id }
    )

    # Mark the deposit as invoiced so the lease page stops flagging it and the
    # charge can't run twice. A nil value = "deposit owed but not yet invoiced",
    # which the lease screen surfaces with Generate / Mark-as-invoiced actions.
    office_lease.update!(deposit_invoiced_at: Time.current)
  rescue StandardError => e
    Honeybadger.notify(e)
    Rails.logger.error("ChargeDeposit failed: #{e.class}: #{e.message}")
    # Don't fail the lease creation if deposit charge fails
    # Admin can manually invoice later
  end
end
