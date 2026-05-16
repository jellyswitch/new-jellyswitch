class Operator::SettingsController < Operator::BaseController
  before_action :require_authentication
  before_action :require_admin_or_superadmin!

  def index
    redirect_to branding_settings_path
  end

  def branding;             end
  def payments;             end
  def doors;                end
  def hours_and_address;    end
  def wifi_and_pixels;      end
  def notifications;        end
  def modules;              end
  def policies;             end

  def update_branding;             head :not_implemented; end
  def update_doors;                head :not_implemented; end
  def import_doors;                head :not_implemented; end
  def update_hours_and_address;    head :not_implemented; end
  def update_wifi_and_pixels;      head :not_implemented; end
  def update_notifications;        head :not_implemented; end
  def update_modules;              head :not_implemented; end
  def update_policies;             head :not_implemented; end

  private

  def require_admin_or_superadmin!
    unless admin? || superadmin?
      redirect_to root_path, alert: "Admins only."
    end
  end
end
