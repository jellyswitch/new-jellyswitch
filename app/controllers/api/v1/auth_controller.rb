class Api::V1::AuthController < Api::V1::BaseController
  skip_before_action :authenticate_api_v1, only: [:login, :signup, :forgot_password, :reset_password, :lookup_operators, :operators]

  # GET /api/v1/auth/operators
  # Public catalog of bookable spaces for the signup-screen dropdown
  # (members shouldn't have to know the subdomain; "Cowork Tahoe" is
  # what they read on the door). Returns operators that have at least
  # one visible location, with the primary location's city to
  # disambiguate ones with similar names.
  def operators
    op_ids = Location.visible.distinct.pluck(:operator_id)
    operators = Operator.where(id: op_ids).order(:name).includes(:locations)

    render json: {
      operators: operators.map { |op|
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

  def signup
    subdomain = params[:subdomain]&.downcase
    operator = Operator.find_by(subdomain: subdomain)
    return render_error('Space not found', status: :not_found) unless operator

    set_current_tenant(operator)

    # Use the same interactor chain as web signup
    location_id = params[:location_id].present? ? params[:location_id] : operator.locations.first&.id

    result = Users::Create.call(
      params: {
        name: params[:name],
        email: params[:email],
        password: params[:password],
        phone: params[:phone],
        original_location_id: location_id,
        terms_accepted: "1",
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

    user = operator.users.find_by("lower(email) = ?", params[:email]&.downcase)
    return render_error('Invalid reset link', status: :unprocessable_entity) unless user&.reset_digest.present?

    unless BCrypt::Password.new(user.reset_digest).is_password?(params[:reset_token])
      return render_error('Invalid reset link', status: :unprocessable_entity)
    end

    if user.reset_sent_at < 2.hours.ago
      return render_error('Reset link has expired', status: :unprocessable_entity)
    end

    if user.update(password: params[:password])
      user.update_columns(reset_digest: nil, reset_sent_at: nil)
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
