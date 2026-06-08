# Serves the canonical brand-spec for the mobile scaffolder / CI. Auth is a
# shared service token (no JWT user), and the operator is resolved by the
# X-Operator-Subdomain header. Inherits Api::V1::BaseController for url_for +
# CSRF skipping, but skips the user-auth/tenant before_actions.
class Api::V1::BrandSpecsController < Api::V1::BaseController
  skip_before_action :authenticate_api_v1, :set_tenant_from_header, :enforce_tenant_scope!, raise: false
  before_action :authenticate_service_token!
  before_action :set_operator

  def show
    result = BrandSpec::Build.call(
      operator: @operator,
      app_icon_url: (@operator.app_icon_image.attached? ? url_for(@operator.app_icon_image) : nil),
      wordmark_url: (@operator.logo_image.attached? ? url_for(@operator.logo_image) : nil)
    )
    render json: result.brand_spec
  end

  private

  def authenticate_service_token!
    expected = ENV["BRAND_SPEC_TOKEN"].to_s
    token = request.headers["Authorization"].to_s.split(" ").last.to_s
    return head(:unauthorized) if expected.blank?
    head :unauthorized unless ActiveSupport::SecurityUtils.secure_compare(token, expected)
  end

  def set_operator
    @operator = Operator.find_by(subdomain: request.headers["X-Operator-Subdomain"].to_s.downcase)
    head :not_found unless @operator
  end
end
