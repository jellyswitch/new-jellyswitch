class Api::V1::PaymentMethodsController < Api::V1::BaseController
  def show
    user = current_api_user
    if user.stripe_customer_id.present?
      begin
        customer = Stripe::Customer.retrieve(
          user.stripe_customer_id,
          stripe_account: current_location.stripe_user_id,
        )
        pm = customer.try(:default_source) || customer.try(:invoice_settings)&.try(:default_payment_method)
        if pm.is_a?(String)
          source = Stripe::Customer.retrieve_source(user.stripe_customer_id, pm, stripe_account: current_location.stripe_user_id)
          return render json: {
            brand: source.brand,
            last4: source.last4,
            exp_month: source.exp_month,
            exp_year: source.exp_year,
          }
        end
      rescue Stripe::InvalidRequestError
        # No valid customer
      end
    end

    render json: { brand: nil, last4: nil }
  end

  def update
    token = params[:stripe_token]
    return render_error('Payment token required') if token.blank?

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
  end
end
