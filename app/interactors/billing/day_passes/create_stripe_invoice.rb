
class Billing::DayPasses::CreateStripeInvoice
  include Interactor

  delegate :day_pass, :token, :operator, :location, :out_of_band, :params, :user_id, :user, to: :context

  def call
    charge_amount = day_pass.day_pass_type.amount_in_cents
    discount_code = context.discount_code

    if discount_code.present?
      discount_amount = discount_code.calculate_discount(charge_amount)
      charge_amount -= discount_amount
      context.discount_amount_in_cents = discount_amount
    end

    @invoice_item = Stripe::InvoiceItem.create({
      customer: day_pass.billable.stripe_customer_id_for_location(location),
      currency: 'usd',
      amount: charge_amount,
      description: day_pass.charge_description
    }, {
      api_key: location.stripe_secret_key,
      stripe_account: location.stripe_user_id
    })

    invoice_args = DayPassableFactory.for(day_pass).invoice_args
    @invoice = Stripe::Invoice.create(
      invoice_args,
      {
        api_key: location.stripe_secret_key,
        stripe_account: location.stripe_user_id
      }
    )

    result = CreateInvoice.call(stripe_invoice: @invoice, location: location)
    if !result.success?
      context.fail!(message: result.message)
    end

    # Track the local invoice so rollback can clean it up if a later step
    # (e.g. ChargeDayPassInvoice) fails. Without this, a charge failure —
    # such as a member with no payment method on file — left an orphaned
    # draft Stripe invoice stranded on the connected account.
    @local_invoice = result.invoice
    day_pass.invoice_id = result.invoice.id
    if !day_pass.save
      context.fail!(message: "There was a problem invoicing this day pass.")
    end

    context.day_pass = day_pass
    context.notifiable = day_pass

    # Record discount redemption if applicable
    if discount_code.present?
      context.discountable = day_pass
      context.user = day_pass.user
      Billing::DiscountCodes::ApplyDiscount.call(context)
    end
  end

  # When a later interactor in the organizer fails (most commonly
  # ChargeDayPassInvoice, when the member has no chargeable card on file),
  # the organizer rolls back in reverse. The local day pass is destroyed by
  # SaveDayPass#rollback, but the Stripe invoice we created here lives on the
  # connected account and would otherwise be stranded as a ghost draft
  # (this is exactly what happened on production: members hit "Payment
  # failed" and were left with orphaned draft day-pass invoices).
  #
  # Clean both sides up — but NEVER a paid invoice: CreateNotifications /
  # ScheduleDayPassEmails run AFTER a successful charge, so if one of those
  # fails we must not void an invoice the member already paid.
  def rollback
    creds = { api_key: location.stripe_secret_key, stripe_account: location.stripe_user_id }

    if @invoice
      begin
        fresh = Stripe::Invoice.retrieve(@invoice.id, creds)
        unless fresh.paid || fresh.status == "paid"
          case fresh.status
          when "draft"
            Stripe::Invoice.delete(@invoice.id, creds)
          when "open", "uncollectible"
            Stripe::Invoice.void_invoice(@invoice.id, creds)
          end
        end
      rescue Stripe::StripeError => e
        Rails.logger.warn("CreateStripeInvoice#rollback: could not clean up Stripe invoice #{@invoice.id}: #{e.class}: #{e.message}")
      end
    end

    if @local_invoice&.persisted?
      @local_invoice.reload
      @local_invoice.destroy unless @local_invoice.status == "paid"
    end
  rescue => e
    # Rollback must never raise — that would mask the original failure.
    Rails.logger.warn("CreateStripeInvoice#rollback: unexpected error: #{e.class}: #{e.message}")
  end
end