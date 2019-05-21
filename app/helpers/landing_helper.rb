module LandingHelper
  def landing_redirect
    if logged_in?
      if admin?
        redirect_to feed_items_path
      else
        if member?
          if approved?
            redirect_to home_path
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
    if member? || admin?
      # they have an active membership
      if !approved? && !admin?
        redirect_to wait_path
      else
        render :home
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
end
