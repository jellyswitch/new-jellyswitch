class Api::V1::PaymentMethodsController < Api::V1::BaseController
  def show
    user = current_api_user
    location = current_location
    stripe_account = location&.stripe_user_id
    # Cards are attached per-location via PaymentProfile, not to a single
    # top-level stripe_customer_id.
    stripe_customer_id = user.stripe_customer_id_for_location(location) if location

    # Stripe.api_key is never set globally in this app — every call
    # must pass it explicitly (see StripeUtils#stripe_request).
    stripe_creds = { api_key: ENV['STRIPE_SECRET_KEY'], stripe_account: stripe_account }

    if stripe_customer_id.present? && stripe_account.present?
      begin
        customer = Stripe::Customer.retrieve(stripe_customer_id, stripe_creds)

        # Try default_source first (legacy Card/Source on customer.default_source)
        ds = customer.try(:default_source)
        if ds.present?
          source = ds.is_a?(String) ?
            Stripe::Customer.retrieve_source(stripe_customer_id, ds, stripe_creds) :
            ds
          return render json: {
            brand: source.try(:brand),
            last4: source.try(:last4),
            exp_month: source.try(:exp_month),
            exp_year: source.try(:exp_year),
          }
        end

        # Then try default_payment_method (PaymentIntents / SetupIntents flow)
        pm_id = customer.try(:invoice_settings)&.try(:default_payment_method)
        if pm_id.present?
          pm = pm_id.is_a?(String) ?
            Stripe::PaymentMethod.retrieve(pm_id, stripe_creds) :
            pm_id
          card = pm.try(:card)
          if card
            return render json: {
              brand: card.try(:brand),
              last4: card.try(:last4),
              exp_month: card.try(:exp_month),
              exp_year: card.try(:exp_year),
            }
          end
        end

        # Last-resort fallback: list payment methods on this customer.
        pms = Stripe::PaymentMethod.list(
          { customer: stripe_customer_id, type: 'card', limit: 1 },
          stripe_creds,
        )
        if pms.data.any?
          card = pms.data.first.card
          return render json: {
            brand: card.try(:brand),
            last4: card.try(:last4),
            exp_month: card.try(:exp_month),
            exp_year: card.try(:exp_year),
          }
        end
      rescue Stripe::InvalidRequestError, Stripe::AuthenticationError, Stripe::APIConnectionError, Stripe::StripeError => e
        Rails.logger.warn("PaymentMethod Stripe error: #{e.class}: #{e.message}")
      end
    end

    render json: { brand: nil, last4: nil }
  end

  def update
    token = params[:stripe_token]
    return render_error('Payment token required') if token.blank?

    begin
      result = Billing::Payment::UpdateUserPayment.call(
        user: current_api_user,
        token: token,
        operator: current_tenant,
        location: current_location,
      )

      if result.success?
        render json: { success: true }
      else
        render_error(result.message || 'Unable to update payment method')
      end
    rescue Stripe::InvalidRequestError, Stripe::APIConnectionError, Stripe::StripeError => e
      render_error("Payment error: #{e.message}")
    end
  end
end
