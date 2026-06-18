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
    @re_engagement_templates = current_tenant.product_email_templates.for_location(@location).re_engagement.order(:product_type)
    @past_member_recovery_templates = current_tenant.product_email_templates.for_location(@location).past_member_recovery.order(:product_type)
    @replenishment_templates = current_tenant.product_email_templates.for_location(@location).replenishment.order(:product_type)
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

  # Prefill a Day Pass Bundle template's body from the operator's existing
  # Day Pass template of the same email_type, as a starting point the operator
  # then edits. Only onboarding/follow_up have a Day Pass counterpart;
  # replenishment is bundle-only.
  def copy_from_day_pass
    @template = current_tenant.product_email_templates.find(params[:id])
    @location = @template.location
    authorize :product_email_template, :update?

    unless @template.product_type == "day_pass_bundle" && %w[onboarding follow_up].include?(@template.email_type)
      flash[:error] = "Prefill from Day Pass is only available for the bundle onboarding and follow-up emails."
      return turbo_redirect(edit_product_email_template_path(@template))
    end

    source = current_tenant.product_email_templates.find_by(
      location: @location, product_type: "day_pass", email_type: @template.email_type
    )

    if source&.body&.present?
      # to_trix_html copies the raw stored body (no view-context rendering),
      # which is what the editor expects on reload.
      @template.update!(body: source.body.to_trix_html)
      flash[:success] = "Copied your Day Pass #{@template.email_type_label} copy. Edit the bundle-specific points (passes remaining, expiry) — note {{date}} doesn't apply to a bundle."
    else
      flash[:error] = "No Day Pass #{@template.email_type_label} template with content to copy from."
    end

    turbo_redirect(edit_product_email_template_path(@template))
  end

  def send_log
    authorize :product_email_template, :send_log?
    @sends = current_tenant.product_email_sends.recent.includes(:user).limit(100)
  end

  private

  def set_location
    @location = current_location
  end

  def template_params
    params.require(:product_email_template).permit(:subject, :body, :follow_up_delay_days)
  end
end
