class Redirector
  include Rails.application.routes.url_helpers

  attr_reader :location, :user, :operator

  def initialize(user:, operator:, location:)
    @user = user
    @operator = operator
    @location = location
  end

  def landing
    return current_location.present?

    if admin? || community_manager? || general_manager?
      if current_tenant.onboarded? || current_tenant.skip_onboarding?
        redirect_to feed_items_path
      else
        redirect_to new_operator_onboarding_path
      end
    else
      if current_user.allowed_in?(current_location)
        if approved?
          if current_user_requires_check_in?
            redirect_to required_checkins_path
          else
            redirect_to home_path
          end
        else
          redirect_to wait_path
        end
      else
        if pending?
          redirect_to activate_path
        else
          redirect_to choose_path
        end
      end
    end
  end

  def home

  end

  private

  def default_url_options
    {
      host: "#{operator.subdomain}.#{ENV['HOST']}"
    }
  end
end