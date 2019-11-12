# typed: false
module LandingHelper
  def landing_redirect
    if logged_in? && current_location.present?
      if admin?
        if current_tenant.onboarded? || current_tenant.skip_onboarding?
          redirect_to feed_items_path
        else
          redirect_to new_operator_onboarding_path
        end
      else
        if member?
          if approved?
            if current_tenant.checkin_required? && !checked_in?
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
  end

  def home_redirect
    if member? || admin? || has_reservation? || has_rsvp?
      # they have an active membership
      if !approved? && !admin?
        redirect_to wait_path
      else
        if !admin? && !always_has_access? && current_tenant.checkin_required? && !checked_in?
          redirect_to required_checkins_path
        else
          render :home
        end
      end
    else
      if logged_in?
        if pending?
          redirect_to activate_path
        else
          if hit_membership_limit?
            redirect_to upgrade_path
          else
            redirect_to choose_path
          end
        end
      else
        # they're logged out
        redirect_to root_path
      end
    end
  end

  private

  def checked_in?
    current_user.checked_in?(current_location)
  end

  def always_has_access?
    current_user.has_building_access_lease? || current_user.always_allow_building_access?
  end

  def has_rsvp?
    current_user.rsvps.going.today.count > 0
  end
end
