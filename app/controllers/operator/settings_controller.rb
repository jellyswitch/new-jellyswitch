class Operator::SettingsController < Operator::BaseController
  before_action :require_admin_or_superadmin!

  def index
    redirect_to settings_branding_path
  end

  def legacy_redirect
    redirect_to settings_branding_path, status: :moved_permanently
  end

  def branding
    @operator = current_operator
  end

  # No update_payments — Stripe Connect is OAuth, not a form. See Payments tab in spec.
  def payments
    @location = selected_location
    @current_location = @location
  end
  def doors
    @operator = current_operator
  end
  def hours_and_address
    @location = selected_location
  end
  def wifi_and_pixels
    @location = selected_location
    @location.tracking_pixels.build if @location.tracking_pixels.empty?
  end
  def notifications
    @operator = current_operator
  end
  def tour_widget
    @operator = current_operator
  end
  def modules
    @operator = current_operator
  end
  # Renamed from `policies` to avoid shadowing `Pundit::Authorization#policies`.
  # Pundit 2.5.2 calls `policies` internally when building its cache_store
  # (`LegacyStore.new(policies)`). When this action method shadowed the
  # helper, Pundit got back the result of `@operator = current_operator`
  # (an AR record) instead of the `{}` cache hash, then crashed on the
  # next `policy(:door)` with "can't write unknown attribute 'door'".
  # Route name (`settings_policies_path`) + URL (`/operator/settings/policies`)
  # stay the same so existing links don't break.
  def policies_tab
    @operator = current_operator
    render :policies
  end

  def update_branding
    @operator = current_operator
    if @operator.update(branding_params)
      redirect_to settings_branding_path, notice: "Branding saved."
    else
      render :branding, status: :unprocessable_entity
    end
  end
  def update_doors
    @operator = current_operator
    if @operator.update(doors_params)
      redirect_to settings_doors_path, notice: "Doors settings saved."
    else
      render :doors, status: :unprocessable_entity
    end
  end

  def import_doors
    result = Onboarding::GetKisiDoors.call(location: selected_location)
    if result.success?
      redirect_to settings_doors_path(location_id: selected_location.id), notice: "Doors imported from KISI."
    else
      redirect_to settings_doors_path(location_id: selected_location.id), alert: "KISI import failed: #{result.message}"
    end
  rescue => e
    redirect_to settings_doors_path(location_id: selected_location.id), alert: "KISI import error: #{e.message}"
  end
  def update_hours_and_address
    @location = selected_location
    if @location.update(hours_and_address_params)
      redirect_to settings_hours_and_address_path(location_id: @location.id), notice: "Hours & address saved."
    else
      render :hours_and_address, status: :unprocessable_entity
    end
  end
  def update_subdomain
    @location = selected_location
    unless superadmin?
      return redirect_to settings_hours_and_address_path(location_id: @location.id), alert: "Not authorized."
    end

    if current_operator.update(subdomain: subdomain_params[:subdomain])
      redirect_to settings_hours_and_address_path(location_id: @location.id),
        notice: "Subdomain updated to #{current_operator.subdomain}.jellyswitch.com."
    else
      redirect_to settings_hours_and_address_path(location_id: @location.id),
        alert: current_operator.errors.full_messages.to_sentence
    end
  end
  def update_wifi_and_pixels
    @location = selected_location
    if @location.update(wifi_and_pixels_params)
      redirect_to settings_wifi_and_pixels_path(location_id: @location.id), notice: "WiFi & pixels saved."
    else
      render :wifi_and_pixels, status: :unprocessable_entity
    end
  end
  def update_notifications
    @operator = current_operator
    if @operator.update(notifications_params)
      redirect_to settings_notifications_path, notice: "Notifications saved."
    else
      render :notifications, status: :unprocessable_entity
    end
  end
  def update_tour_widget
    @operator = current_operator
    if @operator.update(tour_widget_params)
      redirect_to settings_tour_widget_path, notice: "Tour widget settings saved."
    else
      flash.now[:error] = @operator.errors.full_messages.to_sentence
      render :tour_widget, status: :unprocessable_entity
    end
  end
  def update_modules
    @operator = current_operator
    if @operator.update(modules_params)
      redirect_to settings_modules_path, notice: "Modules saved."
    else
      render :modules, status: :unprocessable_entity
    end
  end
  def update_policies
    @operator = current_operator
    if @operator.update(policies_params)
      redirect_to settings_policies_path, notice: "Policies saved."
    else
      render :policies, status: :unprocessable_entity
    end
  end

  private

  def current_operator
    current_tenant
  end
  helper_method :current_operator

  def selected_location
    @selected_location ||= if params[:location_id].present?
      current_operator.locations.find(params[:location_id])
    else
      current_location || current_operator.locations.first
    end
  end
  helper_method :selected_location

  def hours_and_address_params
    params.require(:location).permit(
      :name, :building_address, :city, :state, :zip,
      :latitude, :longitude,
      :time_zone, :working_day_start, :working_day_end,
      :open_sunday, :open_monday, :open_tuesday, :open_wednesday,
      :open_thursday, :open_friday, :open_saturday,
      :building_access_instructions,
      :contact_name, :contact_email, :contact_phone
    )
  end

  def subdomain_params
    params.require(:operator).permit(:subdomain)
  end

  def branding_params
    params.require(:operator).permit(:logo_image, :snippet, :membership_text, :terms_of_service, :google_reviews_url)
  end

  def notifications_params
    params.require(:operator).permit(
      :email_enabled, :reservation_notifications, :membership_notifications,
      :signup_notifications, :day_pass_notifications, :member_feedback_notifications,
      :checkin_notifications, :refund_notifications, :post_notifications,
      :paid_room_reservation_notifications, :sender_email,
      :mailchimp_api_key, :mailchimp_audience_id
    )
  end

  def modules_params
    params.require(:operator).permit(
      :announcements_enabled, :events_enabled, :door_integration_enabled,
      :rooms_enabled, :offices_enabled, :bulletin_board_enabled,
      :credits_enabled, :childcare_enabled, :crm_enabled
    )
  end

  def wifi_and_pixels_params
    params.require(:location).permit(
      :wifi_name, :wifi_password,
      tracking_pixels_attributes: [:id, :operator_id, :name, :script, :always_on, :_destroy]
    )
  end

  def doors_params
    params.require(:operator).permit(
      :kisi_api_key,
      locations_attributes: [:id, :kisi_api_key]
    )
  end

  def policies_params
    params.require(:operator).permit(
      :day_pass_cost,  # virtual; HasDollars writes to day_pass_cost_in_cents
      :refund_fee_percent,
      :cancellation_window_hours,
      :renewal_reminder_days,
      :approval_required,
      :checkin_required
    )
  end

  def tour_widget_params
    params.require(:operator).permit(
      :tour_widget_enabled,
      :tour_widget_thank_you_url,
      :tour_widget_intro_html,
    )
  end

  def require_admin_or_superadmin!
    unless admin? || superadmin?
      redirect_to root_path, alert: "Admins only."
    end
  end
end
