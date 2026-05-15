# Assuming always use this from a Location instance, Operator instance is deprecated
module StripeUtils
  STRIPE_CLASS_MAP = {
    customer: "Customer",
    plan: "Plan",
    subscription: "Subscription",
    invoice: "Invoice",
    invoice_item: "InvoiceItem",
    refund: "Refund",
  }

  STRIPE_CLASS_MAP.each do |key, value|
    define_method("stripe_#{key}") { value }
  end

  def create_stripe_customer(customer)
    return retrieve_stripe_customer(customer) if customer.stripe_customer_id_for_location(self)

    case customer.class.name
    when "User"
      customer_args = {
        email: customer.email,
        description: customer.name,
      }
    when "Organization"
      customer_args = {
        email: customer.email,
        description: customer.name,
      }
    end

    stripe_request(stripe_customer, :create, customer_args)
  end

  def retrieve_stripe_customers
    stripe_request("Customer", :list, {})
  end

  def retrieve_stripe_customer(customer)
    stripe_request(stripe_customer, :retrieve, customer.stripe_customer_id_for_location(self))
  end

  def retrieve_stripe_invoice(invoice)
    stripe_request(stripe_invoice, :retrieve, id: invoice.stripe_invoice_id)
  end

  def create_stripe_refund(invoice, stripe_invoice = nil, amount: nil)
    stripe_invoice = retrieve_stripe_invoice(invoice) unless stripe_invoice
    refund_args = { charge: stripe_invoice.charge, amount: amount || invoice.amount_due }

    stripe_request(stripe_refund, :create, refund_args)
  end

  def retrieve_stripe_refund(refund)
    stripe_request(stripe_refund, :retrieve, id: refund.stripe_refund_id)
  end

  def create_stripe_subscription(subscription, lease: nil, coupon: nil)
    subscribable = StripeSubscriptionFactory.for(subscription, self, lease)
    args = subscribable.subscription_args
    args[:coupon] = coupon if coupon.present?
    stripe_request(stripe_subscription, :create, args)
  end

  def update_stripe_subscription_price(subscription, new_price_in_cents)
    stripe_subscription = retrieve_stripe_subscription(subscription)

    subscription_args = {
      items: [
        {
          id: stripe_subscription.items.data.first.id,
          price_data: {
            currency: "usd",
            product: stripe_subscription.plan.product,
            unit_amount: new_price_in_cents,
            recurring: {
              interval: subscription.plan.stripe_interval,
              interval_count: subscription.plan.stripe_interval_count,
            },
          },
        },
      ],
      proration_behavior: "none",
    }

    Rails.logger.info("Updating subscription price to #{new_price_in_cents}")
    puts subscription_args

    update_stripe_subscription(stripe_subscription.id, subscription_args)
  end

  def update_stripe_subscription(subscription_id, args)
    Stripe::Subscription.update(
      subscription_id,
      args,
      {
        api_key: stripe_secret_key,
        stripe_account: stripe_user_id,
      }
    )
  rescue Stripe::StripeError => e
    Honeybadger.notify(e)
    raise e
  end

  def retrieve_stripe_subscription(subscription)
    stripe_request(stripe_subscription, :retrieve, subscription.stripe_subscription_id)
  end

  def list_stripe_subscriptions
    stripe_request(Subscription, :list, {})
  end

  def create_stripe_plan(plan)
    plan_args = {
      amount: plan.amount_in_cents,
      interval: plan.stripe_interval,
      interval_count: plan.stripe_interval_count,
      product: { name: plan.plan_name },
      currency: "usd",
      id: plan.plan_slug,
    }

    stripe_request(stripe_plan, :create, plan_args)
  end

  def retrieve_stripe_plans
    stripe_request("Plan", :list, {})
  end

  def create_stripe_invoice(user)
    invoice_args = { customer: user.stripe_customer_id_for_location(self) }

    stripe_request(stripe_invoice, :create, invoice_args)
  end

  def create_stripe_invoice_item(user, plan)
    invoice_item_args = {
      customer: user.stripe_customer_id_for_location(self),
      currency: "usd",
      amount: plan.amount_in_cents,
      description: plan.name,
    }

    stripe_request(stripe_invoice_item, :create, invoice_item_args)
  end

  def charge_invoice(invoice)
    stripe_customer = invoice.billable.stripe_customer_for_location(invoice.location)

    unless stripe_customer
      Rails.logger.warn("charge_invoice: No Stripe customer for #{invoice.billable_type} ##{invoice.billable_id}")
      return false
    end

    stripe_invoice = retrieve_stripe_invoice(invoice)

    options = {}
    if stripe_customer.sources.data.count > 0
      options[:source] = stripe_customer.sources.data.first.id
    elsif stripe_customer.invoice_settings&.default_payment_method
      options[:payment_method] = stripe_customer.invoice_settings.default_payment_method
    else
      # Look up payment methods directly
      operator_creds = { api_key: stripe_secret_key, stripe_account: stripe_user_id }
      payment_methods = Stripe::PaymentMethod.list(
        { customer: stripe_customer.id, type: "card" },
        operator_creds
      )
      if payment_methods.data.count > 0
        options[:payment_method] = payment_methods.data.first.id
      else
        Rails.logger.warn("charge_invoice: No payment method for #{invoice.billable_type} ##{invoice.billable_id}")
        return false
      end
    end

    stripe_invoice.pay(options)
  rescue Stripe::InvalidRequestError, Stripe::CardError => e
    Honeybadger.notify(e)
    false
  end

  def mark_invoice_paid(invoice, options = {})
    stripe_invoice = retrieve_stripe_invoice(invoice)

    stripe_invoice.pay(options)
  rescue Stripe::InvalidRequestError => e
    # Don't report expected errors to Honeybadger
    unless e.message.include?('already paid') || e.message.include?('void')
      Honeybadger.notify(e)
    end
    false
  end

  def create_or_update_customer_payment(user, token)
    stripe_customer = retrieve_stripe_customer(user)
    stripe_customer.source = token
    stripe_customer.save
  rescue Stripe::InvalidRequestError => e
    # "token_already_used" means the customer's card was attached on a
    # previous (successful) request and a duplicate POST raced behind it.
    # Treat as success — the card is already on file. Don't notify
    # Honeybadger because this is now an expected duplicate-submit race.
    return stripe_customer if e.message.to_s.include?("more than once") || e.code == "token_already_used"

    Honeybadger.notify(e)
    false
  end

  def update_organization_customer_details(organization, new_email)
    stripe_customer = retrieve_stripe_customer(organization)
    stripe_customer.email = new_email if new_email
    stripe_customer.name = organization.name
    stripe_customer.save
  rescue Stripe::InvalidRequestError => e
    Honeybadger.notify(e)
    false
  end

  def stripe_request(klass, action, request_args)
    operator_stripe_credentials = {
      api_key: stripe_secret_key,
      stripe_account: stripe_user_id,
    }

    stripe_args = [request_args, operator_stripe_credentials]

    "Stripe::#{klass}".constantize.public_send(action, *stripe_args)
  rescue Stripe::InvalidRequestError => e
    Honeybadger.notify(e)
    raise(e)
  end
end
