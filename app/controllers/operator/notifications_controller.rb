class Operator::NotificationsController < Operator::BaseController
  before_action :background_image

  def index
  end

  def reservations
    result = ToggleValue.call(object: current_tenant, value: :reservation_notifications)
    
    if !result.success?
      flash[:error] = result.message
    end

    turbolinks_redirect(notifications_path, action: "replace")
  end
end