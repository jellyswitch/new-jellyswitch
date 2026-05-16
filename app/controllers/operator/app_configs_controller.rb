class Operator::AppConfigsController < Operator::BaseController
  before_action :background_image
  before_action :require_superadmin!

  def index
    authorize :app_configs, :index?
  end

  private

  def require_superadmin!
    redirect_to root_path, alert: "Superadmin only." unless current_user&.superadmin?
  end
end