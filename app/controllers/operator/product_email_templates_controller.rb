class Operator::ProductEmailTemplatesController < Operator::BaseController
  before_action :require_authentication
  before_action :background_image
  before_action :set_location, except: [:send_log]

  def index
    authorize :product_email_template, :index?
    ProductEmailTemplate.seed_defaults_for(current_tenant, location: @location)
    @onboarding_templates = current_tenant.product_email_templates.for_location(@location).onboarding.order(:product_type)
    @follow_up_templates = current_tenant.product_email_templates.for_location(@location).follow_up.order(:product_type)
    @nudge_templates = current_tenant.product_email_templates.for_location(@location).nudge
  end

  def edit
    @template = current_tenant.product_email_templates.find(params[:id])
    @location = @template.location
    authorize :product_email_template, :edit?
  end

  def update
    @template = current_tenant.product_email_templates.find(params[:id])
    @location = @template.location
    authorize :product_email_template, :update?

    if @template.update(template_params)
      flash[:success] = "Email template updated."
      turbo_redirect(product_email_templates_path(location_id: @location&.id))
    else
      flash[:error] = "Unable to update template."
      render :edit, status: 422
    end
  end

  def toggle_enabled
    @template = current_tenant.product_email_templates.find(params[:id])
    authorize :product_email_template, :toggle_enabled?

    result = ToggleValue.call(object: @template, value: :enabled)
    if !result.success?
      flash[:error] = result.message
    end
    turbo_redirect(product_email_templates_path(location_id: @template.location&.id), action: "replace")
  end

  def send_log
    authorize :product_email_template, :send_log?
    @sends = current_tenant.product_email_sends.recent.includes(:user).limit(100)
  end

  private

  def set_location
    @locations = current_tenant.locations.order(:name)
    @location = if params[:location_id].present?
      @locations.find_by(id: params[:location_id])
    else
      @locations.first
    end
  end

  def template_params
    params.require(:product_email_template).permit(:subject, :body, :follow_up_delay_days)
  end
end
