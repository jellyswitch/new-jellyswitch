
class LandingController < ApplicationController
  include SessionsHelper

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
    if params[:error].present?
      flash[:error] = params[:error_description]
      redirect_to landing_url(subdomain: current_user.operator.subdomain)
    else
      location = nil
      if params[:location_id].present?
        location = current_user.operator.locations.find(params[:location_id])
      end
      set_location(location) if location

      result = Operators::FinishStripeConnect.call(
        stripe_code: params[:code],
        operator: current_user.operator,
        location: location,
        webhook_url: stripe_webhooks_url
      )

      if result.success?
        flash[:success] = location ? "Your location has been connected to Stripe" : "Your account has been connected to Stripe."
        redirect_to landing_url(subdomain: current_user.operator.subdomain)
      else
        flash[:error] = "There was a problem storing your Stripe credentials. (#{result.message})"
        if location
          if location.onboarded?
            redirect_to modules_url(subdomain: current_user.operator.subdomain)
          else
            redirect_to landing_url(subdomain: current_user.operator.subdomain)
          end
        else
          if current_user.operator.onboarded?
            redirect_to modules_url(subdomain: current_user.operator.subdomain)
          else
            redirect_to landing_url(subdomain: current_user.operator.subdomain)
          end
        end
      end
    end
  rescue Exception => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(landing_url(subdomain: current_user.operator.subdomain), action: "replace")
  end

end
