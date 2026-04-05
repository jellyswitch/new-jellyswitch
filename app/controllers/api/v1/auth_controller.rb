class Api::V1::AuthController < Api::V1::BaseController
  skip_before_action :authenticate_api_v1, only: [:login]

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
