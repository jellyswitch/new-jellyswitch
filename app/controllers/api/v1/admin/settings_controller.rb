class Api::V1::Admin::SettingsController < Api::V1::Admin::BaseController
  # Mobile admin notification toggle key => real boolean column on operators.
  # The mobile settings screen renders one Switch per key returned by
  # #notifications, so this map is the single source of truth for BOTH the read
  # (GET notifications_config) and the write (PATCH notifications_config) paths,
  # keeping them symmetric — a toggle saved via PATCH reads back identically.
  #
  # The four keys this endpoint originally used (new_member_notification,
  # new_booking_notification, new_feedback_notification, daily_digest) were never
  # operator columns: GET hid that with .try (always false) and PATCH raised
  # ActiveModel::UnknownAttributeError, 500-ing every save. Room bookings are
  # split into free vs paid to mirror the web settings page. daily_digest is
  # dropped — no column backs it and no digest delivery exists.
  NOTIFICATION_TOGGLES = {
    new_member_notification:        :signup_notifications,
    free_room_booking_notification: :reservation_notifications,
    paid_room_booking_notification: :paid_room_reservation_notifications,
    new_feedback_notification:      :member_feedback_notifications,
  }.freeze

  def show
    loc = current_location
    return render_error("No location found", status: :not_found) unless loc
    op = current_tenant

    render json: {
      # Location settings
      id: loc.id,
      name: loc.name,
      building_address: loc.building_address,
      city: loc.city,
      state: loc.state,
      zip: loc.zip,
      contact_name: loc.contact_name,
      contact_email: loc.contact_email,
      contact_phone: loc.contact_phone,
      wifi_name: loc.wifi_name,
      wifi_password: loc.wifi_password,
      working_day_start: loc.working_day_start,
      working_day_end: loc.working_day_end,
      building_access_instructions: loc.building_access_instructions,
      time_zone: loc.time_zone,
      open_monday: loc.open_monday,
      open_tuesday: loc.open_tuesday,
      open_wednesday: loc.open_wednesday,
      open_thursday: loc.open_thursday,
      open_friday: loc.open_friday,
      open_saturday: loc.open_saturday,
      open_sunday: loc.open_sunday,
      modules: module_flags(loc),
      # Operator settings
      operator_name: op.name,
      operator_subdomain: op.subdomain,
      snippet: op.try(:snippet),
      membership_text: op.try(:membership_text),
      approval_required: op.try(:approval_required?) || false,
      checkin_required: op.try(:checkin_required?) || false,
      ios_url: op.try(:ios_url),
      android_url: op.try(:android_url),
      bundle_id: op.try(:bundle_id),
      has_logo: op.try(:logo_image)&.attached? || false,
      has_terms: op.try(:terms_of_service)&.attached? || false,
      refund_fee_percent: op.try(:refund_fee_percent) || 0,
      cancellation_window_hours: op.try(:cancellation_window_hours) || 0,
    }
  end

  def update
    loc = current_location
    op = current_tenant

    # Update location settings
    loc_params = settings_params
    loc.update(loc_params) if loc_params.keys.any?

    # Update operator settings
    op_data = operator_params
    op.update(op_data) if op_data.keys.any?

    render json: { success: true }
  end

  def modules
    render json: module_flags(current_location)
  end

  def update_modules
    loc = current_location

    if loc.update(module_params)
      render json: module_flags(loc)
    else
      render_error(loc.errors.full_messages.join(', '))
    end
  end

  def notifications
    render json: notification_state(current_tenant)
  end

  def update_notifications
    operator = current_tenant

    updates = NOTIFICATION_TOGGLES.each_with_object({}) do |(api_key, column), attrs|
      next unless params.key?(api_key)
      attrs[column] = ActiveModel::Type::Boolean.new.cast(params[api_key])
    end

    if operator.update(updates)
      render json: notification_state(operator)
    else
      render_error(operator.errors.full_messages.join(', '))
    end
  end

  private

  def settings_params
    params.permit(
      :working_day_start, :working_day_end,
      :contact_name, :contact_email, :contact_phone,
      :wifi_name, :wifi_password,
      :building_address, :city, :state, :zip,
      :building_access_instructions, :time_zone,
      :open_monday, :open_tuesday, :open_wednesday,
      :open_thursday, :open_friday, :open_saturday, :open_sunday
    )
  end

  def operator_params
    params.permit(
      :name, :snippet, :membership_text,
      :approval_required, :checkin_required,
      :ios_url, :android_url, :bundle_id,
      :refund_fee_percent,
      :cancellation_window_hours,
    )
  end

  def module_params
    params.permit(
      :announcements_enabled, :events_enabled,
      :door_integration_enabled, :rooms_enabled,
      :offices_enabled, :bulletin_board_enabled,
      :credits_enabled
    )
  end

  def notification_state(operator)
    NOTIFICATION_TOGGLES.transform_values { |column| operator.public_send(column) }
  end

  def module_flags(loc)
    {
      announcements_enabled: loc.announcements_enabled,
      events_enabled: loc.events_enabled,
      door_integration_enabled: loc.door_integration_enabled,
      rooms_enabled: loc.rooms_enabled,
      offices_enabled: loc.offices_enabled,
      bulletin_board_enabled: loc.bulletin_board_enabled,
      credits_enabled: loc.credits_enabled,
      # childcare removed from mobile app
      crm_enabled: loc.crm_enabled,
    }
  end
end
