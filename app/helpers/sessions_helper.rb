module SessionsHelper
  # Logs in the given user
  def log_in(user)
    session[:user_id] = user.id
  end

  def set_location(location)
    session[:location_id] = location.id
  end

  def unset_location
    session.delete(:location_id)
    cookies.delete(:location_id)
    @current_location = nil
  end

  # Returns the current logged-in user (if any)
  def current_user
    if (user_id = session[:user_id])
      @current_user ||= User.find_by(id: session[:user_id])
    elsif (user_id = cookies.signed[:user_id])
      user = User.find_by(id: user_id)
      if user && user.authenticated?(cookies[:remember_token])
        log_in(user)
        @current_user = user
      end
    end
  end

  def current_checkin
    if !logged_in?
      return nil
    else
      current_user.checkins.for_location(current_location).open.first
    end
  end

  def current_location
    # In case I"m a superadmin and my location is set to a different operator
    if session[:location_id]
      loc = Location.unscoped.find_by(id: session[:location_id])
      
      if loc && loc.operator != current_tenant
        unset_location
      end
    end

    return @current_location if @current_location
    
    if (location_id = session[:location_id])
      @current_location ||= Location.find_by(id: location_id)
    elsif (location_id = cookies.signed[:location_id])
      current_location = Location.find_by(id: location_id)
      if current_location
        set_location(location)
        @current_location = current_location
      else
        raise "No locations configured."
      end
    elsif Location.count == 1
      set_location(Location.first)
      @current_location = Location.first
    end
  end

  def logged_in?
    !current_user.nil?
  end

  def admin?
    logged_in? && current_user.admin?
  end

  def superadmin?
    logged_in? && current_user.superadmin?
  end

  def member?
    current_user.present? && (current_user.member?(current_tenant) || current_user.checked_in?(current_location) )
  end

  def pending?
    current_user.present? && current_user.pending?
  end

  def approved?
    current_user.present? && current_user.approved?
  end

  def hit_membership_limit?
    current_user.present? && current_user.subscriptions.active.any? do |sub|
      !sub.has_days_left?
    end
  end

  def log_out
    checkout
    forget(current_user)
    session.delete(:user_id)
    unset_location
    @current_user = nil
  end

  def authenticate!
    if !logged_in?
      flash[:notice] = "Please log in."
      redirect_to root_path
    end
  end

  def remember(user)
    user.remember
    cookies.permanent.signed[:user_id] = user.id
    cookies.permanent[:remember_token] = user.remember_token
  end

  def forget(user)
    user.forget
    cookies.delete(:user_id)
    cookies.delete(:remember_token)
  end

  def checkout
    if current_checkin.present?
      result = Checkins::Checkout.call(
        checkin: current_checkin
      )
      if !result.success?
        flash[:error] = result.message
      end
    end
  end
end
