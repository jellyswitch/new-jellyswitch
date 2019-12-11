class Operator::ModulesController < Operator::BaseController
  before_action :background_image
  before_action { authorize :module }

  def index
  end

  def announcements
    result = ToggleValue.call(object: current_tenant, value: :announcements_enabled)
    
    if !result.success?
      flash[:error] = result.message
    end

    turbolinks_redirect(modules_path, action: "replace")
  end
end