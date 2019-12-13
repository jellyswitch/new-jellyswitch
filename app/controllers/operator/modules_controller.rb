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

  def events
    result = ToggleValue.call(object: current_tenant, value: :events_enabled)
    
    if !result.success?
      flash[:error] = result.message
    end

    turbolinks_redirect(modules_path, action: "replace")
  end

  def door_integration
    result = ToggleValue.call(object: current_tenant, value: :door_integration_enabled)
    
    if !result.success?
      flash[:error] = result.message
    end

    turbolinks_redirect(modules_path, action: "replace")
  end

  def rooms
    result = ToggleValue.call(object: current_tenant, value: :rooms_enabled)
    
    if !result.success?
      flash[:error] = result.message
    end

    turbolinks_redirect(modules_path, action: "replace")
  end

  def offices
    if current_tenant.has_active_office_leases?
      flash[:error] = "Terminate active office leases before disabling."
    else
      result = ToggleValue.call(object: current_tenant, value: :offices_enabled)
      
      if !result.success?
        flash[:error] = result.message
      end
    end

    turbolinks_redirect(modules_path, action: "replace")
  end
end