class Api::V1::AuthController < Api::V1::BaseController
  skip_before_action :authenticate_api_v1, only: [:login, :signup, :forgot_password, :reset_password]

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
    result = Users::Create.call(
      params: {
        name: params[:name],
        email: params[:email],
        password: params[:password],
        phone: params[:phone],
        original_location_id: operator.locations.first&.id,
        terms_accepted: "1",
      },
      operator: operator,
      admin_created: false,
    )

    if result.success?
      token = generate_token(result.user)
      render json: { token: token, user: user_json(result.user) }, status: :created
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
      user.create_reset_digest
      user.send_password_reset_email
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
      location: user.original_location&.name,
      operator: user.operator.name,
      has_profile_photo: user.has_profile_photo?,
    }
  end
end
