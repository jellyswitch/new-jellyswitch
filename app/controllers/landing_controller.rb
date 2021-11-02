# typed: true
class LandingController < ApplicationController
  def index
    if logged_in?
      if superadmin?
        redirect_to operators_path
      else
        redirect_to landing_url(subdomain: current_user.operator.subdomain)
      end
    end
  end

  def welcome
    render :typeform, layout: false
  end

  def stripe_connect_setup
    Rails.logger.warn "Params: #{params.inspect}"

    if params[:error].present?
      Rails.logger.warn "params['error'].present? TRUE"

      flash[:error] = params[:error_description]
      redirect_to landing_url(subdomain: current_user.operator.subdomain)
    else
      Rails.logger.warn "params['error'].present? FALSE"
      Rails.logger.warn "params[:code] is #{params[:code]}"
      Rails.logger.warn "current_user.operator is #{current_user.operator}"
      Rails.logger.warn "stripe_webhooks_url is #{stripe_webhooks_url}"

      result = Operators::FinishStripeConnect.call(
        stripe_code: params[:code],
        operator: current_user.operator,
        webhook_url: stripe_webhooks_url
      )

      if result.success?
        flash[:success] = "Your account has been connected to Stripe."
        redirect_to landing_url(subdomain: current_user.operator.subdomain)
      else
        flash[:error] = "There was a problem storing your Stripe credentials. (#{result.message})"
        Rails.logger.warn "current_user.operator.subdomain is #{current_user.operator.subdomain}"
        if current_user.operator.onboarded?
          Rails.logger.warn "REDIRECTING TO modules_url"
          redirect_to modules_url(subdomain: current_user.operator.subdomain)
        else
          Rails.logger.warn "REDIRECTING TO landing_url"
          redirect_to landing_url(subdomain: current_user.operator.subdomain)
        end
      end
    end
  rescue Exception => e
    Rollbar.error(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbolinks_redirect(landing_url(subdomain: current_user.operator.subdomain), action: "replace")
  end

end
