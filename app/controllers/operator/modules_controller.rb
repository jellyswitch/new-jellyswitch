class Operator::ModulesController < Operator::BaseController
  before_action :background_image
  before_action { authorize :module }

  def index
  end

  def announcements
    setting(:announcements_enabled)
  end

  def events
    setting(:events_enabled)
  end

  def door_integration
    setting(:door_integration_enabled)
  end

  def rooms
    setting(:rooms_enabled)
  end

  def credits
    setting(:credits_enabled)
  end

  def offices
    if current_tenant.has_active_office_leases?
      flash[:error] = "Terminate active office leases before disabling."
      turbolinks_redirect(modules_path, action: "replace")
    else
      setting(:offices_enabled)
    end
  end

  private

  def setting(symbol)
    result = ToggleValue.call(object: current_tenant, value: symbol)
    
    if !result.success?
      flash[:error] = result.message
    end

    turbolinks_redirect(modules_path, action: "replace")
  end
end