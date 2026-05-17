
class LandingController < ApplicationController
  include SessionsHelper

  def index
    if logged_in?
      if superadmin?
        redirect_to operators_path
      else
        redirect_to landing_url(subdomain: current_user.operator.subdomain), allow_other_host: true
      end
    end
  end

  def welcome
    render :typeform, layout: false
  end

  def stripe_connect_setup
    if params[:error].present?
      flash[:error] = params[:error_description]
      redirect_to settings_payments_url(subdomain: current_user.operator.subdomain), allow_other_host: true
    else
      location_id = params[:state]

      location = current_user.operator.locations.find(location_id)
      set_location(location) if location

      result = Operators::FinishStripeConnect.call(
        stripe_code: params[:code],
        operator: current_user.operator,
        location: location,
        webhook_url: stripe_webhooks_url
      )

      if result.success?
        flash[:success] = location ? "Your location has been connected to Stripe" : "Your account has been connected to Stripe."
        if session.delete(:onboarding_in_progress)
          redirect_to new_stripe_connect_operator_onboarding_index_path(subdomain: current_user.operator.subdomain), allow_other_host: true
        else
          redirect_to settings_payments_url(subdomain: current_user.operator.subdomain), allow_other_host: true
        end
      else
        flash[:error] = "There was a problem storing your Stripe credentials. (#{result.message})"
        redirect_to settings_payments_url(subdomain: current_user.operator.subdomain), allow_other_host: true
      end
    end
  rescue Exception => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(settings_payments_url(subdomain: current_user.operator.subdomain), action: "replace")
  end

end
