class Operator::BaseController < ApplicationController
  set_current_tenant_through_filter
  before_action :set_tenant_based_on_subdomain

  before_action :store_ios_token, if: :logged_in?
  before_action :store_android_token, if: :logged_in?
  before_action :set_resource_scopes
  around_action :set_time_zone, if: :current_location
  before_action :reset_location
  before_action :require_complete_profile
  before_action :set_navigation
  before_action :touch_last_active, if: :logged_in?

  layout "operator"

  def set_tenant_based_on_subdomain
    # &. — hosts with no subdomain at all (`Host: localhost`, raw IPs from
    # bot probes) must reach the presence guard, not crash on nil.downcase.
    subdomain = request.subdomains.first&.downcase
    return unless subdomain.present?

    operator = Operator.find_by(subdomain: subdomain)
    return unless operator.present?

    set_current_tenant(operator)
  end

  def background_image
    @background_image = if current_tenant.present?
      if current_location.present? && current_location.has_photo?
        current_location.background_image
      else
        current_tenant.background_image
      end
    end
  end

  def pundit_user
    UserContext.new(current_user, current_tenant, current_location)
  end

  # Defense-in-depth for the "&amp;-encoded query string" class of bug.
  #
  # When a link's href is built in JS and Turbo snapshots the page for its
  # cache, the DOM is serialized via outerHTML — which HTML-escapes the
  # href's `&` separators back into `&amp;`. On a WebView cache-restore +
  # navigation the literal "amp;" can survive into the request query string,
  # so Rails parses `...&amp;room_id=5927...` as a param key named
  # "amp;room_id" and `params[:room_id]` comes back nil → RecordNotFound.
  #
  # Re-map any `amp;`-prefixed key back to its intended name (without
  # clobbering a correctly-named key if both somehow arrive). Notify so we
  # retain visibility into whether the upstream component fix fully stops it.
  # Wired up via `prepend_before_action` in the controllers most exposed to
  # this (the reservation flow, which builds multi-param hrefs in JS).
  def recover_html_escaped_query_params
    mangled = params.keys.select { |k| k.to_s.start_with?("amp;") }
    return if mangled.empty?

    mangled.each do |k|
      real = k.to_s.sub(/\Aamp;/, "")
      params[real] = params[k] unless params.key?(real)
    end

    Honeybadger.notify(
      "Recovered &amp;-escaped query params",
      context: {
        controller: self.class.name,
        action: action_name,
        path: request.fullpath,
        mangled_keys: mangled,
      },
    )
  end

  # Telemetry-only handler: report the full request context to Honeybadger
  # before letting Rails handle the 404 as usual. Wired up via `rescue_from`
  # in specific controllers (currently the reservation flows) where blind
  # 404s have been hard to diagnose from logs alone — e.g. an admin clicks
  # "Reserve Later" on a hidden room and lands on a Rails 404, but the
  # exact `room_id`/`user_id`/`day` that caused `find` to miss never
  # makes it into Honeybadger because RecordNotFound isn't a 500.
  #
  # Re-raises so the user-facing behavior is unchanged.
  def report_record_not_found_with_context(error)
    Honeybadger.notify(error, context: {
      controller: self.class.name,
      action: action_name,
      method: request.method,
      path: request.path,
      fullpath: request.fullpath,
      params: params.to_unsafe_h,
      user_id: current_user&.id,
      user_email: current_user&.email,
      operator_subdomain: request.subdomains.first,
      current_tenant_id: current_tenant&.id,
      current_location_id: current_location&.id,
      referer: request.referer,
      user_agent: request.user_agent,
    })
    raise error
  end

  def store_ios_token
    if logged_in?
      match = request.user_agent.match(/.*deviceToken: (.*)/)
      return if match.nil? || match[1].blank?
      token = match[1]
      # update_columns bypasses AR callbacks (including searchkick reindex).
      # The push token isn't a searchable field, so skipping the index call
      # avoids a hard dependency on Bonsai/OpenSearch for every page load.
      current_user.update_columns(ios_token: token) if current_user.ios_token != token
    end
  end

  def store_android_token
    if logged_in?
      match = request.user_agent.match(/.*token: (.*)/)
      return if match.nil? || match[1].blank?
      token = match[1]
      current_user.update_columns(android_token: token) if current_user.android_token != token
    end
  end

  def set_navigation
    @navigation = NavigationFactory.for(
      logged_in?,
      current_tenant,
      current_location,
      current_user)
  end

  private

  # Post-purchase email hand-off (ADR 0017). Approved buyers are redirected to
  # /home, which — unlike /wait — carries no `shared/_app_download_nudge`
  # partial, so they'd otherwise miss the pointer to the "how to use the space"
  # email. Append that same line to the post-purchase success flash, but ONLY on
  # the approved (home-bound) path: unapproved buyers land on /wait where the
  # partial already shows it, so guarding on approved? avoids a duplicate line.
  #
  # Keep the wording in sync with shared/_app_download_nudge.html.erb.
  def append_email_handoff(message)
    return message unless approved?

    "#{message} Check your email for how to use the space."
  end

  def set_resource_scopes
    if ActsAsScopable.current_scope_resources.empty?
      ActsAsScopable.current_scope_resources = [current_tenant, current_location]
    end

    if current_tenant.blank?
      redirect_to status: 404
    end
  end

  def set_time_zone(&block)
    Time.use_zone(current_location.time_zone, &block)
  end

  def reset_location
    if current_location.blank?
      if logged_in?
        log_out
        redirect_to root_path
      elsif (request.get? && request.format.html?) && !(controller_name == "landing" && action_name == "index")
        # If the user tries go go anywhere that is not the landing page, they should be redirected to the landing page where they will select location
        redirect_to root_path
      elsif !(controller_name == "landing" && action_name == "index")
        # Logged-out, non-HTML or non-GET request to a non-landing controller
        # with no current_location — we can't sensibly redirect, but the action
        # would NoMethodError on nil downstream. Halt cleanly instead.
        head :unauthorized
      end
    end
  end

  def require_authentication
    unless current_user
      store_location

      flash[:error] = "You must be logged in to access this page."
      turbo_redirect(login_path, action: :replace)
    end
  end

  def touch_last_active
    return unless current_user
    if current_user.last_active_at.nil? || current_user.last_active_at < 5.minutes.ago
      current_user.update_column(:last_active_at, Time.current)
    end
  end

  def require_complete_profile
    # Disabled: was blocking existing members who had blank phone or TOS fields.
    # Profile completion is encouraged via the edit form banner but no longer
    # enforced via redirect, so members can always access doors and the app.
  end

  def store_location
    # Don't store the location for certain requests
    return if request.xhr? ||
            request.format.json? ||
            request.path.start_with?('/login') ||
            request.path.start_with?('/logout')

    session[:return_to] = request.fullpath
  end
end
