class Redirector
  include Rails.application.routes.url_helpers

  attr_reader :location, :user, :operator, :user_context

  def initialize(user:, operator:, location:)
    @user = user
    @operator = operator
    @location = location

    @user_context = UserContext.new(user, operator, location)
  end

  def landing
    if !location.present?
      return
    end
    
    if user_context.admin? || user_context.community_manager? || user_context.general_manager?
      if operator.onboarded? || operator.skip_onboarding?
        feed_items_path
      else
        new_operator_onboarding_path
      end
    else
      if user.allowed_in?(location)
        if user_context.approved?
          if user_context.requires_check_in?
            required_checkins_path
          else
            home_path
          end
        else
          wait_path
        end
      else
        if user_context.pending?
          activate_path
        else
          choose_path
        end
      end
    end
  end

  def home
    # Todo
  end

  private

  def default_url_options
    {
      host: "#{operator.subdomain}.#{ENV['HOST']}"
    }
  end
end