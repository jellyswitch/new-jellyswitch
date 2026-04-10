class Api::V1::Admin::DiscountCodesController < Api::V1::Admin::BaseController
  def index
    codes = DiscountCode.where(operator: current_tenant)

    render json: codes.map { |c|
      {
        id: c.id,
        code: c.code,
        discount_type: c.discount_type,
        discount_value: c.discount_value,
        usage_count: c.discount_redemptions.count,
        active: c.active,
      }
    }
  end

  def create
    code = DiscountCode.new(code_params)
    code.operator = current_tenant

    if code.save
      render json: { id: code.id, code: code.code }, status: :created
    else
      render_error(code.errors.full_messages.join(', '))
    end
  end

  def update
    code = DiscountCode.find(params[:id])

    if code.update(code_params)
      render json: { id: code.id, code: code.code }
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
end
