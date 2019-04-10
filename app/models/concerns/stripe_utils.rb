module StripeUtils
  STRIPE_CLASS_MAP = {
    customer: 'Customer',
    plan: 'Plan',
    subscription: 'Subscription',
    invoice: 'Invoice',
    invoice_item: 'InvoiceItem',
    refund: 'Refund',
  }

  STRIPE_CLASS_MAP.each do |key, value|
    define_method("stripe_#{key}") { value }
  end

  def create_stripe_customer(customer)
    case customer.class.name
    when 'User'
      customer_args = { email: customer.email }
    when 'Organization'
      customer_args = { description: "Customer for organization #{name}" }
    end

    stripe_request(stripe_customer, :create, customer_args)
  end

  def retrieve_stripe_customer(customer)
    stripe_request(stripe_customer, :retrieve, customer.stripe_customer_id)
  end

  def retrieve_stripe_invoice(invoice)
    stripe_request(stripe_invoice, :retrieve, id: invoice.stripe_invoice_id)
  end

  def create_stripe_refund(invoice, stripe_invoice = nil)
    stripe_invoice = retrieve_stripe_invoice(invoice) unless stripe_invoice
    refund_args = { charge: stripe_invoice.charge, amount: invoice.amount_paid }

    stripe_request(stripe_refund, :create, refund_args)
  end

  def retrieve_stripe_refund(refund)
    stripe_request(stripe_refund, :retrieve, id: refund.stripe_refund_id)
  end

  def create_stripe_subscription(subscriber, subscription, start_day = nil)
    subscription_args = {
      customer: subscriber.stripe_customer_id,
      items: [{ plan: subscription.plan.stripe_plan_id }]
    }

    if subscriber.out_of_band? && start_day.present?
      subscription_args.merge!(
        billing: 'send_invoice',
        billing_cycle_anchor: start_day.to_i,
        days_until_due: 30,
      )
    elsif subscriber.out_of_band?
      subscription_args.merge!(billing: 'send_invoice', days_until_due: 30)
    elsif start_day.present?
      subscription_args.merge!(billing: 'charge_automatically', billing_cycle_anchor: start_day.to_i)
    else
      subscription_args.merge!(billing: 'charge_automatically')
    end

    stripe_request(stripe_subscription, :create, subscription_args)
  end

  def create_stripe_plan(plan)
    plan_args = {
      amount: plan.amount_in_cents,
      interval: plan.stripe_interval,
      product: { name: plan.plan_name },
      currency: 'usd',
      id: plan.plan_slug
    }

    stripe_request(stripe_plan, :create, plan_args)
  end

  def create_stripe_invoice(user)
    invoice_args = { customer: user.stripe_customer_id }

    stripe_request(stripe_invoice, :create, invoice_args)
  end

  def create_stripe_invoice_item(user, plan)
    invoice_item_args = {
      customer: user.stripe_customer_id,
      currency: 'usd',
      amount: plan.amount_in_cents,
      description: plan.name,
    }

    stripe_request(stripe_invoice_item, :create, invoice_item_args)
  end

  def mark_invoice_paid(invoice, options = {})
    stripe_invoice = retrieve_stripe_invoice(invoice)

    stripe_invoice.pay(options)
  rescue Stripe::InvalidRequestError => e
    Rollbar.error(e)
    false
  end

  private

  def stripe_request(klass, action, request_args)
    operator_stripe_credentials = {
      api_key: stripe_secret_key,
      stripe_account: stripe_user_id
    }

    stripe_args = [request_args, operator_stripe_credentials]

    "Stripe::#{klass}".constantize.public_send(action, *stripe_args)
  rescue Stripe::InvalidRequestError => e
    Rollbar.error(e)
  end
end
