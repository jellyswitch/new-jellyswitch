class Operator::AppConfigsController < Operator::BaseController
  before_action :background_image
  
  def index
    authorize :app_configs, :index?
  end
end