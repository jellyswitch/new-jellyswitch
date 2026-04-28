class Api::V1::Admin::BaseController < Api::V1::BaseController
  before_action :require_admin!

  private

  def require_admin!
    unless admin_user?
      render json: { error: 'Unauthorized' }, status: :forbidden
    end
  end

  def admin_user?
    current_api_user&.admin? ||
      current_api_user&.role.in?(%w[admin general_manager community_manager])
  end
end
