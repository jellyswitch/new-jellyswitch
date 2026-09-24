class Api::V1::BaseController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false
  before_action :authenticate_api_v1
  before_action :set_tenant_from_header
  before_action :enforce_tenant_scope!
  around_action :disable_search_indexing

  def disable_search_indexing
    Searchkick.callbacks(false) { yield }
  end

  private

  def authenticate_api_v1
    token = request.headers['Authorization']&.split(' ')&.last
    return render_unauthorized unless token

    begin
      payload = JWT.decode(token, jwt_secret, true, algorithm: 'HS256').first
      @current_api_user  = User.find(payload['user_id'])
      @api_token_payload = payload
    rescue JWT::DecodeError, ActiveRecord::RecordNotFound
      render_unauthorized
    end
  end

  def current_api_user
    @current_api_user
  end

  # Which client minted the bearer token. nil for the phone apps (their tokens
  # carry no claim); "garmin" for tokens issued by Api::V1::GarminController#pair.
  # Lets endpoints label side effects (door punches) without trusting a client-
  # supplied param.
  def api_client
    @api_token_payload&.dig('client')
  end

  # Server-side conversion log for app purchases (see Conversion.record).
  # The mobile app has no Ahoy visit, so the row is credited to the buyer's
  # stored first-touch (or "app" when they signed up in the app). Never raises.
  def record_api_conversion(kind, subject:, amount_in_cents: nil, user: current_api_user)
    Conversion.record(
      kind: kind,
      operator: current_tenant,
      location: current_location,
      user: user,
      subject: subject,
      amount_cents: amount_in_cents,
      surface: "app",
      actor: current_api_user,
    )
  end

  def set_tenant_from_header
    subdomain = request.headers['X-Operator-Subdomain']
    if subdomain.present?
      operator = Operator.find_by(subdomain: subdomain.downcase)
      ActsAsTenant.current_tenant = operator if operator
    elsif current_api_user
      ActsAsTenant.current_tenant = current_api_user.operator
    end
  end

  # Cross-tenant boundary for the whole API: an authenticated user may only
  # operate within their own operator, regardless of the X-Operator-Subdomain
  # header. Platform staff (the `superadmin` *boolean*) may cross operators; the
  # per-operator "superadmin" role may not. Unauthenticated actions (login,
  # signup, operator lookup) have no user yet and pass through.
  def enforce_tenant_scope!
    return if current_api_user.nil?
    return if current_api_user.superadmin == true
    return if current_tenant && current_api_user.operator_id == current_tenant.id

    render json: { error: 'Forbidden' }, status: :forbidden
  end

  def current_tenant
    ActsAsTenant.current_tenant
  end

  def set_current_tenant(tenant)
    ActsAsTenant.current_tenant = tenant
  end

  def current_location
    current_api_user&.active_location
  end

  def render_unauthorized
    render json: { error: 'Unauthorized' }, status: :unauthorized
  end

  def render_error(message, status: :unprocessable_entity)
    render json: { error: message }, status: status
  end

  def jwt_secret
    Rails.application.secret_key_base
  end

  def generate_token(user)
    payload = {
      user_id: user.id,
      operator_id: user.operator_id,
      exp: 30.days.from_now.to_i,
    }
    JWT.encode(payload, jwt_secret, 'HS256')
  end
end
