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

    creds = { api_key: location.stripe_secret_key, stripe_account: location.stripe_user_id }

    # Create a one-time invoice item for the deposit. The idempotency key is
    # keyed on the lease, so the "Generate deposit invoice" recovery action (or
    # any retry) reuses this same pending item instead of creating a second one
    # that Stripe would sweep into the invoice — the double-charge this fixes.
    invoice_item = Stripe::InvoiceItem.create(
      {
        customer: stripe_customer_id,
        amount: office_lease.deposit_amount_in_cents,
        currency: "usd",
        description: "Deposit / Setup Fee for #{office_lease.office.name}"
      },
      creds.merge(idempotency_key: "deposit-item-#{office_lease.id}")
    )

    # Create and finalize the invoice immediately (also idempotency-keyed).
    stripe_invoice =
      begin
        Stripe::Invoice.create(
          {
            customer: stripe_customer_id,
            auto_advance: true,
            description: "Deposit for #{office_lease.office.name} lease"
          },
          creds.merge(idempotency_key: "deposit-invoice-#{office_lease.id}")
        )
      rescue Stripe::StripeError
        # Invoice creation failed — delete the pending item so it isn't swept
        # into the lessee's NEXT invoice as a phantom deposit charge.
        Stripe::InvoiceItem.delete(invoice_item.id, creds) rescue nil
        raise
      end

    # Stamp BEFORE finalize: the item is attached and auto_advance:true means
    # Stripe will finalize + collect on its own, so the deposit is effectively
    # committed here. Stamping now closes the window where a finalize/update
    # hiccup left deposit_invoiced_at nil and the recovery action re-charged.
    office_lease.update!(deposit_invoiced_at: Time.current)

    Stripe::Invoice.finalize_invoice(stripe_invoice.id, {}, creds)
  rescue StandardError => e
    Honeybadger.notify(e)
    Rails.logger.error("ChargeDeposit failed: #{e.class}: #{e.message}")
    # Don't fail the lease creation if deposit charge fails
    # Admin can manually invoice later
  end
end
