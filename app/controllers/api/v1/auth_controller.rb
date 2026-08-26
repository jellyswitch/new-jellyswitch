class Api::V1::AuthController < Api::V1::BaseController
  skip_before_action :authenticate_api_v1, only: [:login, :signup, :forgot_password, :reset_password, :lookup_operators, :operators, :request_login_code, :verify_login_code]

  # GET /api/v1/auth/operators
  #
  # Returns the calling app's operator (scoped via X-Operator-Subdomain).
  # Used by the mobile signup screen to populate the operator's visible
  # locations array — important for multi-location operators like
  # Untethered (Zephyr Cove + main) where the user picks which location
  # to be signed up at.
  #
  # Used to return the entire jellyswitch catalog (every operator with a
  # visible location) unscoped — that leaked Innogrove / InSpark / Studio
  # entries into Cowork Tahoe's branded app picker, alongside any
  # low-quality / spammy operator signups. Now hard-scoped to the
  # X-Operator-Subdomain header set by the api client.
  #
  # If a caller doesn't identify a tenant, returns an empty array — the
  # signup form's default already targets `brand.subdomain` so the user
  # can still complete signup; the picker is just empty.
  def operators
    operators = if current_tenant
      Operator.where(id: current_tenant.id).includes(:locations)
    else
      Operator.none
    end

    render json: {
      operators: operators.order(:name).map { |op|
        visible_locations = op.locations.visible.order(:id)
        primary = visible_locations.first
        {
          id:            op.id,
          name:          op.name,
          subdomain:     op.subdomain,
          # Backward-compat keys (still consumed by SignupScreen.js):
          location_name: primary&.name,
          city:          primary&.city,
          state:         primary&.state,
          # New keys (preferred going forward):
          primary_location_name: primary&.name,
          primary_city:          primary&.city,
          primary_state:         primary&.state,
          primary_latitude:      primary&.latitude,
          primary_longitude:     primary&.longitude,
          # Terms of Service — exposed pre-login so the mobile signup screen can
          # show a real "I agree" checkbox + viewable TOS (web parity). Null when
          # the operator hasn't uploaded a TOS, so the client hides the checkbox.
          has_terms_of_service: op.terms_of_service.attached?,
          terms_of_service_url: (
            op.terms_of_service.attached? ?
              Rails.application.routes.url_helpers.rails_blob_url(op.terms_of_service, host: request.host_with_port) :
              nil
          ),
          locations: visible_locations.map { |l|
            { id: l.id, name: l.name, latitude: l.latitude, longitude: l.longitude }
          },
        }
      }
    }
  end

  def login
    subdomain = params[:subdomain]&.downcase
    operator = Operator.find_by(subdomain: subdomain)
    return render_error('Space not found', status: :not_found) unless operator

    set_current_tenant(operator)

    user = operator.users.find_by("lower(email) = ?", params[:email]&.downcase)
    if user&.authenticate(params[:password])
      token = generate_token(user)
      render json: {
        token: token,
        user: user_json(user),
      }
    else
      render_error('Invalid email or password', status: :unauthorized)
    end
  end

  # Passwordless login, step 1 — email a single-use Login Code (ADR 0016).
  # Always reports success so the response never reveals whether the email has
  # an account (mirrors #forgot_password). Rate-limited at the Rack layer.
  def request_login_code
    subdomain = params[:subdomain]&.downcase
    operator = Operator.find_by(subdomain: subdomain)
    return render_error('Space not found', status: :not_found) unless operator

    set_current_tenant(operator)

    user = operator.users.find_by("lower(email) = ?", params[:email]&.downcase)
    if user
      begin
        user.generate_login_code
        user.send_login_code_email
      rescue => e
        Rails.logger.error("Login code email failed: #{e.message}")
      end
    end

    render json: { success: true, message: "If an account exists with that email, we've sent a login code." }
  end

  # Passwordless login, step 2 — verify the code and issue the same credential
  # as password login. A successful verify also confirms the email (see
  # User#verify_login_code). Generic failure so a wrong/expired code reveals
  # nothing; the per-code attempt cap + Rack throttle bound brute force.
  def verify_login_code
    subdomain = params[:subdomain]&.downcase
    operator = Operator.find_by(subdomain: subdomain)
    return render_error('Space not found', status: :not_found) unless operator

    set_current_tenant(operator)

    user = operator.users.find_by("lower(email) = ?", params[:email]&.downcase)
    if user&.verify_login_code(params[:code])
      token = generate_token(user)
      render json: { token: token, user: user_json(user) }
    else
      render_error('Invalid or expired login code', status: :unauthorized)
    end
  end

  def signup
    subdomain = params[:subdomain]&.downcase
    operator = Operator.find_by(subdomain: subdomain)
    return render_error('Space not found', status: :not_found) unless operator

    set_current_tenant(operator)

    # Honeypot: legitimate mobile builds never send `_hp`. A scripted client
    # replaying the public web form (which has the hidden field) trips it.
    # Silent generic failure so the caller can't tell it was flagged.
    return render_error('Unable to sign up. Please try again.', status: :unprocessable_entity) if params[:_hp].present?

    # Bot protection — LENIENT rollout phase (follow-up to web operator signup,
    # PR #479). We can't hard-require a token yet: store builds in the wild do
    # NOT send one, and TURNSTILE_SECRET is set in production, so requiring it
    # would fail every existing mobile signup with `missing-input-response`.
    #
    # So: verify ONLY when the client actually sends `cf-turnstile-response`
    # (i.e. a new build), and pass untokened requests through untouched. Every
    # verification is logged via Turnstile::Verifier(context: "mobile_signup"),
    # giving us per-error-code telemetry to watch token adoption climb before
    # we flip this endpoint to strict enforcement (see the strict-cutover plan).
    # The Verifier short-circuits to success when TURNSTILE_SECRET is blank
    # (test/dev), so this is a no-op locally.
    turnstile_token = params["cf-turnstile-response"]
    if turnstile_token.present?
      turnstile = Turnstile::Verifier.call(
        token: turnstile_token,
        remote_ip: request.remote_ip,
        context: "mobile_signup",
      )
      unless turnstile.success?
        return render_error('Captcha verification failed. Please try again.', status: :unprocessable_entity)
      end
    end

    # Use the same interactor chain as web signup. Default to the first
    # *visible* location so a signup with no location_id never auto-assigns
    # the new user to a hidden test/archived space — and reject a
    # caller-supplied location_id that isn't a *visible* location of this
    # operator (e.g. a stale link or cached build pointing at a deprecated
    # space), which previously stranded self-signups on orphaned locations.
    requested_location_id = params[:location_id].presence&.to_i
    visible_location_ids = operator.locations.visible.pluck(:id)
    location_id =
      if requested_location_id && visible_location_ids.include?(requested_location_id)
        requested_location_id
      else
        visible_location_ids.first
      end

    result = Users::Create.call(
      params: {
        name: params[:name],
        email: params[:email],
        password: params[:password],
        phone: params[:phone],
        original_location_id: location_id,
        # Record the member's ACTUAL consent instead of hard-coding "1". The app
        # only sends terms_accepted=true after they check the TOS box; if the
        # operator has no TOS, the box is hidden and this stays falsey (nothing
        # to consent to). Users::Save sets terms_accepted_at only when "1", so a
        # missing/false value never blocks signup — it just isn't recorded as
        # consent (accurate, and far safer than fabricating agreement).
        terms_accepted: (ActiveModel::Type::Boolean.new.cast(params[:terms_accepted]) ? "1" : "0"),
        marketing_consent: params[:marketing_opt_in] != false,
        home_latitude:  params[:home_latitude],
        home_longitude: params[:home_longitude],
      },
      operator: operator,
      admin_created: false,
    )

    if result.success?
      token = generate_token(result.user)
      render json: { token: token, user: user_json(result.user), locations: operator.locations.visible.map { |l| { id: l.id, name: l.name } } }, status: :created
    else
      render_error(result.message, status: :unprocessable_entity)
    end
  end

  def forgot_password
    subdomain = params[:subdomain]&.downcase
    operator = Operator.find_by(subdomain: subdomain)
    return render_error('Space not found', status: :not_found) unless operator

    set_current_tenant(operator)
    user = operator.users.find_by("lower(email) = ?", params[:email]&.downcase)

    if user
      begin
        user.create_reset_digest
        user.send_password_reset_email
      rescue => e
        Rails.logger.error("Password reset email failed: #{e.message}")
      end
    end

    # Always return success to prevent email enumeration
    render json: { success: true, message: 'If an account exists with that email, password reset instructions have been sent.' }
  end

  def reset_password
    subdomain = params[:subdomain]&.downcase
    operator = Operator.find_by(subdomain: subdomain)
    return render_error('Space not found', status: :not_found) unless operator

    set_current_tenant(operator)

    # Same predicates as the web flow (Operator::PasswordResetsController) so the
    # two reset surfaces can't drift apart on what counts as a valid token.
    user = operator.users.find_by("lower(email) = ?", params[:email]&.downcase)
    unless user&.valid_reset_token?(params[:reset_token])
      return render_error('Invalid reset link', status: :unprocessable_entity)
    end

    if user.password_reset_expired?
      return render_error('Reset link has expired', status: :unprocessable_entity)
    end

    if user.update(password: params[:password])
      user.clear_reset_digest!
      token = generate_token(user)
      render json: { token: token, user: user_json(user) }
    else
      render_error(user.errors.full_messages.join(', '), status: :unprocessable_entity)
    end
  end

  def lookup_operators
    email = params[:email]&.downcase&.strip
    return render json: { operators: [] } if email.blank?

    # Intentionally NOT filtering by `archived` — #login allows archived
    # users to authenticate (a soft-deleted account isn't a forbidden
    # account), so lookup must surface their operators too. Otherwise the
    # mobile brand-sticky flow auto-routes them to whichever space they
    # happen to be active on, silently demoting cross-tenant admins
    # whose original tenant record is archived.
    users = User.where("lower(email) = ?", email)
    operators = users.map(&:operator).uniq.compact

    # Don't reveal if email exists when there are no results — return empty
    render json: {
      operators: operators.map { |op|
        { name: op.name, subdomain: op.subdomain }
      },
      multiple: operators.length > 1,
    }
  end

  def refresh
    token = generate_token(current_api_user)
    render json: { token: token, user: user_json(current_api_user) }
  end

  # Authenticated resend of the email-confirmation link, powering the app's
  # "verify your email" nudge (we no longer block unconfirmed members from
  # logging in). Scoped to the token's own user, so there's no enumeration
  # surface. Always reports success to keep the response uniform.
  def resend_confirmation
    user = current_api_user
    if user && !user.email_confirmed?
      user.generate_confirmation_token
      user.send_confirmation_email
    end
    render json: { success: true, message: "If your email needs confirming, we've sent a fresh link. Please check your inbox." }
  rescue => e
    Rails.logger.error("API resend confirmation failed: #{e.message}")
    Honeybadger.notify(e) if defined?(Honeybadger)
    render json: { success: true, message: "If your email needs confirming, we've sent a fresh link. Please check your inbox." }
  end

  private

  def user_json(user)
    {
      id: user.id,
      name: user.name,
      email: user.email,
      phone: user.phone,
      approved: user.approved?,
      role: user.role,
      admin: user.admin?,
      superadmin: user.superadmin?,
      # Surfaced so the app can show a "verify your email" nudge on login —
      # parity with the web layout banner (neither path blocks unconfirmed
      # members anymore).
      email_confirmed: user.email_confirmed?,
      needs_email_confirmation: user.needs_email_confirmation?,
      location: user.original_location&.name,
      operator: user.operator.name,
      has_profile_photo: user.has_profile_photo?,
      # Match /me's logic so the mobile client can make correct routing
      # decisions immediately on login response (preventing the
      # "WelcomeScreen flash" race between login and the first /me).
      has_active_coverage: compute_has_active_coverage(user),
    }
  end

  def compute_has_active_coverage(user)
    loc = user.current_location || user.original_location
    zone = loc&.time_zone.presence || 'UTC'
    today = Time.current.in_time_zone(zone).to_date
    user.has_active_subscription? ||
      user.day_passes.where(day: today).any? ||
      (loc.present? && user.has_active_lease?(loc)) ||
      user.admin_or_manager?(loc) ||
      user.superadmin?
  end
end
