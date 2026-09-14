
class CreateInvoice
  include Interactor

  delegate :stripe_invoice, :location, :created_at, to: :context

  def call
    invoice = Invoice.find_by(stripe_invoice_id: stripe_invoice.id)
    if invoice.present?
      context.fail!(message: "Invoice #{invoice.number} already exists")
    end

    customer = stripe_invoice.customer

    # TODO: put type in stripe invoice metadata
    billable = User.find_by_stripe_customer_id(customer) || Organization.find_by(stripe_customer_id: customer)

    if billable.nil?
      context.error_message = 'nonexistent-customer'
      context.fail!(message: "Cannot find billable with stripe customer id #{customer}")
    end

    invoice_date = Time.at(stripe_invoice.created).to_datetime

    due_date = nil
    if stripe_invoice.due_date.present?
      due_date = Time.at(stripe_invoice.due_date).to_datetime
    end

    params = {
      billable: billable,
      operator_id: billable.operator.id,
      amount_due: stripe_invoice.amount_due.to_i,
      amount_paid: stripe_invoice.amount_paid.to_i,
      number: stripe_invoice.try(:number),
      stripe_invoice_id: stripe_invoice.id,
      date: invoice_date,
      due_date: due_date,
      status: stripe_invoice.status
    }

    if created_at.present?
      params[:created_at] = created_at
      params[:updated_at] = created_at
    end

    if location.present?
      params[:location_id] = location.id
    else
      # Triggered from a webhook with no location in hand. The Stripe customer
      # is per-location (UserPaymentProfile), so it pins the location exactly;
      # billable.location (users.current_location) is only a fallback — a fresh
      # signup can have a payment profile before current_location is ever set.
      params[:location_id] = resolve_location_id(billable, customer)
    end

    invoice = Invoice.create!(params)

    context.invoice = invoice

    result = Billing::Invoices::AddCreditsToSubscribable.call(
      invoice: invoice,
      stripe_invoice: stripe_invoice
    )

    if !result.success?
      context.fail!(message: result.message)
    end
  end

  private

  def resolve_location_id(billable, stripe_customer_id)
    if billable.is_a?(User)
      profile_location_id = UserPaymentProfile
        .where(user_id: billable.id, stripe_customer_id: stripe_customer_id)
        .pick(:location_id)
      return profile_location_id if profile_location_id
    end

    billable.location&.id || billable.try(:original_location)&.id
  end
end
