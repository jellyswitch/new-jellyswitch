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
  def notifications;        end
  def modules;              end
  def policies;             end

  def update_branding
    if current_operator.update(branding_params)
      redirect_to settings_branding_path, notice: "Branding saved."
    else
      render :branding, status: :unprocessable_entity
    end
  end
  def update_doors;                head :not_implemented; end
  def import_doors;                head :not_implemented; end
  def update_hours_and_address;    head :not_implemented; end
  def update_wifi_and_pixels;      head :not_implemented; end
  def update_notifications;        head :not_implemented; end
  def update_modules;              head :not_implemented; end
  def update_policies;             head :not_implemented; end

  private

  def current_operator
    current_tenant
  end

  def branding_params
    params.require(:operator).permit(:logo_image, :snippet, :membership_text, :terms_of_service, :google_reviews_url)
  end

  def require_admin_or_superadmin!
    unless admin? || superadmin?
      redirect_to root_path, alert: "Admins only."
    end
  end
end
