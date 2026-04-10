class Api::V1::StripeController < Api::V1::BaseController
  def config
    location = current_location
    render json: {
      publishable_key: location&.stripe_publishable_key,
      account_id: location&.stripe_user_id,
    }
  end

  def setup_intent
    location = current_location
    user = current_api_user

    # Ensure user has a Stripe customer on this location's connected account
    begin
      result = CreateStripeCustomer.call(user: user, location: location)
    rescue Stripe::InvalidRequestError, Stripe::APIConnectionError, Stripe::StripeError => e
      return render_error("Stripe error: #{e.message}")
    end
    customer_id = user.stripe_customer_id_for_location(location)

    return render_error('Unable to create customer') unless customer_id

    # Create SetupIntent on the connected account
    begin
      setup_intent = Stripe::SetupIntent.create(
        { customer: customer_id, payment_method_types: ['card'] },
        { stripe_account: location.stripe_user_id },
      )

      render json: {
        client_secret: setup_intent.client_secret,
        setup_intent_id: setup_intent.id,
      }
    rescue Stripe::InvalidRequestError, Stripe::APIConnectionError, Stripe::StripeError => e
      render_error("Stripe error: #{e.message}")
    end
  end

  def validate_discount_code
    code = params[:code]&.strip
    return render_error('Please enter a code') if code.blank?

    result = Billing::DiscountCodes::ValidateCode.call(
      code: code,
      operator: current_tenant,
    )

    if result.success?
      dc = result.discount_code
      render json: {
        valid: true,
        code: dc.code,
        discount_type: dc.discount_type,
        discount_value: dc.discount_value,
        description: dc.try(:description),
      }
    else
      render json: { valid: false, error: result.message || 'Invalid code' }
    end
  end
end
