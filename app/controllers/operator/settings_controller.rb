class Operator::SettingsController < Operator::BaseController
  before_action :require_admin_or_superadmin!

  def index
    redirect_to settings_branding_path
  end

  def branding
    @operator = current_operator
  end

  # No update_payments — Stripe Connect is OAuth, not a form. See Payments tab in spec.
  def payments;             end
  def doors;                end
  def hours_and_address;    end
  def wifi_and_pixels;      end
  def notifications
    @operator = current_operator
  end
  def modules
    @operator = current_operator
  end
  def policies
    @operator = current_operator
  end

  def update_branding
    @operator = current_operator
    if @operator.update(branding_params)
      redirect_to settings_branding_path, notice: "Branding saved."
    else
      render :branding, status: :unprocessable_entity
    end
  end
  def update_doors;                head :not_implemented; end
  def import_doors;                head :not_implemented; end
  def update_hours_and_address;    head :not_implemented; end
  def update_wifi_and_pixels;      head :not_implemented; end
  def update_notifications
    @operator = current_operator
    if @operator.update(notifications_params)
      redirect_to settings_notifications_path, notice: "Notifications saved."
    else
      render :notifications, status: :unprocessable_entity
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

  def require_admin_or_superadmin!
    unless admin? || superadmin?
      redirect_to root_path, alert: "Admins only."
    end
  end
end
