class Api::V1::Admin::NotificationPreferencesController < Api::V1::Admin::BaseController
  TOGGLES = %i[
    reservation_notifications
    paid_room_reservation_notifications
    day_pass_notifications
    membership_notifications
    signup_notifications
    checkin_notifications
    member_feedback_notifications
    refund_notifications
    post_notifications
  ].freeze

  def show
    render json: prefs_json(current_tenant)
  end

  def update
    attrs = params.require(:notification_preferences).permit(*TOGGLES)
    if current_tenant.update(attrs)
      render json: prefs_json(current_tenant)
    else
      render_error(current_tenant.errors.full_messages.first)
    end
  end

  private

  def prefs_json(op)
    TOGGLES.each_with_object({}) { |key, h| h[key] = !!op.try(key) }
  end
end
