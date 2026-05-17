
class Operator::OperatorsController < Operator::BaseController
  before_action :background_image

  def show
    find_operator
    authorize @operator
  end

  def stripe_connect_setup # seems like not used anymore, now using the one in LandingController#stripe_connect_setup
    find_operator
    if params[:error].present?
      flash[:error] = params[:error_description]
    else
      result = Operators::FinishStripeConnect.call(
        stripe_code: params[:code],
        operator: @operator,
        webhook_url: stripe_webhooks_url
      )

      if result.success?
        flash[:success] = "Your account has been connected to Stripe."
      else
        flash[:error] = "There was a problem storing your Stripe credentials. (#{result.message})"
      end
    end
    redirect_to operator_path(@operator, subdomain: @operator.subdomain)
  rescue Exception => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  def approval_required
    find_operator
    result = ToggleValue.call(object: @operator, value: :approval_required)
    
    if !result.success?
      flash[:error] = result.message
    end

    turbo_redirect(operator_path(@operator, subdomain: @operator.subdomain), action: "replace")
  end

  def checkin_required
    find_operator
    result = ToggleValue.call(object: @operator, value: :checkin_required)
    
    if !result.success?
      flash[:error] = result.message
    end

    turbo_redirect(operator_path(@operator, subdomain: @operator.subdomain), action: "replace")
  end

  private

  def find_operator
    @operator = current_tenant
  end


end