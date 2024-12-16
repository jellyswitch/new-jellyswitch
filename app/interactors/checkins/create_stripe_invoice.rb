
class Checkins::CreateStripeInvoice
  include Interactor

  delegate :checkin, to: :context

  def call
    location = checkin.location
    if generate_invoice?
      @invoice_item = Stripe::InvoiceItem.create({
        customer: checkin.billable.stripe_customer_id_for_location(location),
        currency: 'usd',
        amount: checkin.charge_amount,
        description: checkin.charge_description
      }, {
        api_key: location.stripe_secret_key,
        stripe_account: location.stripe_user_id
      })

      invoice_args = CheckInableFactory.for(checkin).invoice_args
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

      if !checkin.update(invoice_id: result.invoice.id)
        context.fail!(message: "There was a problem invoicing this day pass.")
      end
    end
  end

  private

  def generate_invoice?
    if checkin.user.operator.production? || checkin.user.operator.subdomain == "southlakecoworking"
      !(checkin.user.member?(location, day= checkin.datetime_in) ||
        checkin.user.has_active_day_pass? ||
        checkin.user.has_active_lease? ||
        checkin.user.admin_of_location?(location))
    else
      false
    end
  end
end