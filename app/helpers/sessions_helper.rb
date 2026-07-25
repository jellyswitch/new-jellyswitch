module SessionsHelper
  # Logs in the given user
  def log_in(user)
    session[:user_id] = user.id
    ahoy.authenticate(user)

    # sets the user's current location to the current location, unless operator onboarding
    subdomain = request.subdomains.first&.downcase
    if subdomain != "app" && current_location.present?
      user.update(current_location: current_location)
    end
  end

  def set_location(location)
    session[:location_id] = location.id
    cookies.signed[:location_id] = { value: location.id, expires: 1.year.from_now }
    @current_location = location
  end

  def unset_location
    session.delete(:location_id)
    cookies.delete(:location_id)
    @current_location = nil
  end

  # Returns the current logged-in user (if any)
  def current_user
    if (user_id = session[:user_id])
      @current_user ||= begin
        user = User.find_by(id: user_id)
        user if session_user_valid_for_tenant?(user)
      end
    elsif (user_id = cookies.signed[:user_id])
      user = User.find_by(id: user_id)
      if user && user.authenticated?(cookies[:remember_token]) && session_user_valid_for_tenant?(user)
        log_in(user)
        @current_user = user
      end
    end
  end

  # The session cookie is domain-wide (`domain: :all` in
  # config/initializers/sessions.rb), so one `_magic_session` spans every
  # tenant subdomain. Only honor a session/remember-me user on hosts belonging
  # to their own operator — otherwise a member logged in on operator A was
  # silently logged in on operator B's site as their A record, and anything
  # they bought there (invoices, day passes) attached to a user B's admin
  # can't even see. Platform staff (the `superadmin` BOOLEAN, not the
  # per-operator "superadmin" role — mirrors
  # Api::V1::BaseController#enforce_tenant_scope!) may cross operators, e.g.
  # the app-subdomain → tenant hop and cross-tenant masquerade. A mismatch
  # leaves the session and cookies untouched: the visitor is simply treated as
  # logged out on this host, and stays logged in on their own tenant's site.
  def session_user_valid_for_tenant?(user)
    return false if user.nil?
    return true if !defined?(current_tenant) || current_tenant.nil?
    return true if user.superadmin == true

    user.operator_id == current_tenant.id
  end

  def current_checkin
    if !logged_in?
      nil
    else
      if current_location.present?
        current_user.checkins.for_location(current_location).open.first
      else
        nil
      end
    end
  end

  def current_location
    if !defined?(current_tenant)
      return nil
    end

    # In case I"m a superadmin and my location is set to a different operator
    if session[:location_id]
      loc = Location.unscoped.find_by(id: session[:location_id])

      if loc && loc.operator != current_tenant
        unset_location
      end
    end

    # if I already have a current location set, return it
    return @current_location if @current_location

    if !respond_to?(:session, true) || !respond_to?(:cookies, true)
      # No request context (e.g., background job or Turbo broadcast)
      return nil
    end

    return nil unless current_tenant

    # Resolve from the most specific signal available — session, then signed
    # cookie, then the user's persisted preference — but ONLY accept a location
    # that belongs to the current tenant. A stale or cross-operator id (a deleted
    # location, or a preference pointing at another operator) must not "win" its
    # branch and block resolution: previously a present-but-unresolvable id
    # short-circuited the single-location fallback, so current_location returned
    # nil and reset_location logged the user out (the Tahoe Longhouse incident).
    resolved =
      current_tenant.locations.find_by(id: session[:location_id]) ||
      current_tenant.locations.find_by(id: cookies.signed[:location_id]) ||
      current_tenant.locations.find_by(id: current_user&.current_location_id)

    # Single-location operators always resolve to their only location — there is
    # nothing to choose, so never fall through to the picker.
    resolved ||= current_tenant.locations.first if current_tenant.locations.count == 1

    if resolved
      # Persist the resolution (and self-heal a stale session/cookie) unless the
      # session already points at it.
      set_location(resolved) unless session[:location_id] == resolved.id
      @current_location = resolved
    else
      # Multi-location operator with no valid selection — expected. Clean up any
      # dangling cookie; reset_location will route the user to the picker.
      cookies.delete(:location_id) if cookies.signed[:location_id].present?
      nil
    end
  end

  def update_location(location)
    checkout
    unset_location
    set_location(location)

    # if there is an logged in user, set their current location
    if logged_in? && current_user
      current_user.update(current_location: location)
    end

    flash[:notice] = "Switched to location #{location.name}."
  end

  def logged_in?
    !current_user.nil?
  end

  def admin?
    logged_in? && current_user.admin_of_location?(current_location)
  end

  def superadmin?
    logged_in? && current_user.superadmin?
  end

  def community_manager?
    logged_in? && current_user.community_manager_of_location?(current_location)
  end

  def general_manager?
    logged_in? && current_user.general_manager_of_location?(current_location)
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
    session.delete(:email)
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
    user&.forget
    cookies.delete(:user_id)
    cookies.delete(:remember_token)
  end

  def checkout
    if current_checkin.present?
      result = Checkins::Checkout.call(
        checkin: current_checkin,
      )
      if !result.success?
        flash[:error] = result.message
      end
    end
  end
end
