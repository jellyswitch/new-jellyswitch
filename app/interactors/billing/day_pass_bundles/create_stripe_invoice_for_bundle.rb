class Billing::DayPassBundles::CreateStripeInvoiceForBundle
  include Interactor

  delegate :day_pass_bundle, :operator, :location, :user, to: :context

  def call
    # Charge the pack price exactly once. This is the flat SKU price the
    # operator set — NOT quantity × anything. Volume discount is baked in.
    charge_amount = day_pass_bundle.day_pass_type.amount_in_cents

    creds = { api_key: location.stripe_secret_key, stripe_account: location.stripe_user_id }

    @invoice_item = Stripe::InvoiceItem.create({
      customer: day_pass_bundle.billable.stripe_customer_id_for_location(location),
      currency: "usd",
      amount: charge_amount,
      description: day_pass_bundle.charge_description
    }, creds.merge(idempotency_key: "bundle-item-#{day_pass_bundle.id}"))

    # Out-of-band customers pay via mailed invoice (send_invoice / days_until_due).
    # In-band customers are charged immediately by ChargeBundleInvoice (charge_automatically,
    # auto_advance: false so we finalize + pay synchronously).
    invoice_args = if day_pass_bundle.billable.out_of_band?
      {
        customer: day_pass_bundle.billable.stripe_customer_id_for_location(location),
        auto_advance: false,
        billing: "send_invoice",
        days_until_due: 30
      }
    else
      {
        customer: day_pass_bundle.billable.stripe_customer_id_for_location(location),
        auto_advance: false,
        billing: "charge_automatically"
      }
    end

    @stripe_invoice =
      begin
        Stripe::Invoice.create(invoice_args, creds)
      rescue Stripe::StripeError
        # Invoice creation failed after the item — this interactor's own
        # rollback won't run, so delete the pending item or it gets swept into
        # the member's NEXT invoice as a phantom charge.
        Stripe::InvoiceItem.delete(@invoice_item.id, creds) rescue nil
        raise
      end

    result = CreateInvoice.call(stripe_invoice: @stripe_invoice, location: location)
    unless result.success?
      context.fail!(message: result.message)
    end

    @local_invoice = result.invoice
    day_pass_bundle.invoice_id = result.invoice.id
    unless day_pass_bundle.save
      context.fail!(message: "There was a problem invoicing this day pass bundle.")
    end

    context.day_pass_bundle = day_pass_bundle
    context.notifiable = day_pass_bundle
  end

  def rollback
    creds = { api_key: location.stripe_secret_key, stripe_account: location.stripe_user_id }

    if @stripe_invoice
      begin
        fresh = Stripe::Invoice.retrieve(@stripe_invoice.id, creds)
        unless fresh.paid || fresh.status == "paid"
          case fresh.status
          when "draft"
            Stripe::Invoice.delete(@stripe_invoice.id, creds)
          when "open", "uncollectible"
            Stripe::Invoice.void_invoice(@stripe_invoice.id, creds)
          end
        end
      rescue Stripe::StripeError => e
        Rails.logger.warn("CreateStripeInvoiceForBundle#rollback: could not clean up Stripe invoice #{@stripe_invoice.id}: #{e.class}: #{e.message}")
      end
    end

    if @local_invoice&.persisted?
      @local_invoice.reload
      @local_invoice.destroy unless @local_invoice.status == "paid"
    end

    # Clean up the pending item too — a deleted draft releases its items back to
    # pending. Guarded — a no-op if already consumed by a finalized/paid invoice.
    if @invoice_item
      begin
        Stripe::InvoiceItem.delete(@invoice_item.id, creds)
      rescue Stripe::StripeError
        # already consumed by a finalized invoice — nothing to release
      end
    end
  rescue => e
    Rails.logger.warn("CreateStripeInvoiceForBundle#rollback: unexpected error: #{e.class}: #{e.message}")
  end
end
