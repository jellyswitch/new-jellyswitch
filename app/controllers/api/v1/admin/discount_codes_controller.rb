class Api::V1::Admin::DiscountCodesController < Api::V1::Admin::BaseController
  def index
    codes = DiscountCode.where(operator: current_tenant).order(created_at: :desc)
    render json: codes.map { |c| code_json(c) }
  end

  def create
    code = DiscountCode.new(code_params)
    code.operator = current_tenant

    if code.save
      render json: code_json(code), status: :created
    else
      render_error(code.errors.full_messages.join(', '))
    end
  end

  def update
    code = DiscountCode.find(params[:id])

    if code.update(code_params)
      render json: code_json(code)
    else
      render_error(code.errors.full_messages.join(', '))
    end
  end

  def destroy
    code = DiscountCode.find(params[:id])
    code.destroy
    render json: { success: true }
  end

  private

  def code_params
    params.permit(:code, :discount_type, :discount_value, :applies_to,
      :active, :expires_at, :max_redemptions)
  end

  def code_json(c)
    expired = c.try(:expires_at).present? && c.expires_at < Time.current
    {
      id: c.id,
      code: c.code,
      discount_type: c.discount_type,
      discount_value: c.discount_value,
      applies_to: c.try(:applies_to) || 'all',
      max_redemptions: c.try(:max_redemptions),
      expires_at: c.try(:expires_at)&.strftime("%B %e, %Y"),
      usage_count: c.discount_redemptions.count,
      active: c.active,
      expired: expired,
    }
  end
end
