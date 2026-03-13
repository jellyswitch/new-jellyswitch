class Operator::ProductEmailTemplatesController < Operator::BaseController
  before_action :require_authentication
  before_action :background_image

  def index
    authorize :product_email_template, :index?
    ProductEmailTemplate.seed_defaults_for(current_tenant)
    @onboarding_templates = current_tenant.product_email_templates.onboarding.order(:product_type)
    @follow_up_templates = current_tenant.product_email_templates.follow_up.order(:product_type)
    @nudge_templates = current_tenant.product_email_templates.nudge
  end

  def edit
    @template = current_tenant.product_email_templates.find(params[:id])
    authorize :product_email_template, :edit?
  end

  def update
    @template = current_tenant.product_email_templates.find(params[:id])
    authorize :product_email_template, :update?

    if @template.update(template_params)
      flash[:success] = "Email template updated."
      turbo_redirect(product_email_templates_path)
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
    turbo_redirect(product_email_templates_path, action: "replace")
  end

  def send_log
    authorize :product_email_template, :send_log?
    @sends = current_tenant.product_email_sends.recent.includes(:user).limit(100)
  end

  private

  def template_params
    params.require(:product_email_template).permit(:subject, :body, :follow_up_delay_days)
  end
end
