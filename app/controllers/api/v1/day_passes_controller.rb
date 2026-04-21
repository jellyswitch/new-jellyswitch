class Api::V1::DayPassesController < Api::V1::BaseController
  def types
    types = DayPassType.where(operator: current_tenant)
      .where(location: current_location)
      .where(available: true, visible: true)
      .order(:amount_in_cents)

    render json: types.map { |t|
      {
        id: t.id,
        name: t.name,
        price: t.amount_in_cents,
        included_meeting_minutes: t.try(:included_meeting_room_minutes),
      }
    }
  end

  def index
    passes = current_api_user.day_passes
      .where(operator: current_tenant)
      .order(day: :desc)
      .limit(20)

    render json: passes.map { |dp|
      {
        id: dp.id,
        date: dp.day&.strftime("%B %e, %Y"),
        type_name: dp.day_pass_type&.name,
        paid: dp.stripe_charge_id.present?,
        complimentary: dp.complimentary,
      }
    }
  end

  def create
    day_pass_type = DayPassType.find(params[:day_pass_type_id])
    date = params[:date].present? ? Date.parse(params[:date]) : Date.current
    token = params[:stripe_token]
    discount_code = params[:discount_code]

    # Use the same interactor chain as the web app
    interactor = token.present? ?
      Billing::DayPasses::UpdatePaymentAndCreateDayPass :
      Billing::DayPasses::CreateDayPass

    interactor_params = {
      user_id: current_api_user.id,
      token: token,
      operator: current_tenant,
      location: current_location,
      params: {
        day_pass_type: day_pass_type.id.to_s,
        day: date,
        operator_id: current_tenant.id,
      },
    }

    # Apply discount code if provided
    if discount_code.present?
      dc = DiscountCode.find_by(code: discount_code, operator: current_tenant)
      interactor_params[:discount_code] = dc if dc&.active?
    end

    result = interactor.call(**interactor_params)

    if result.success?
      dp = result.day_pass || DayPass.where(user: current_api_user).order(created_at: :desc).first
      render json: { success: true, id: dp&.id, date: date.strftime("%B %e, %Y") }, status: :created
    else
      render_error(result.message || 'Unable to create day pass')
    end
  end

  # Legacy redeem endpoint — forwards to apply_code.
  def redeem
    apply_code
  end

  # POST /api/v1/day_passes/apply_code
  # Single unified endpoint: validates a DiscountCode (percent_off or
  # amount_off). 100% off codes effectively mean a free day pass. The
  # client applies the returned discount at purchase time.
  def apply_code
    code = params[:code]&.strip
    return render_error('Please enter a code') if code.blank?

    result = Billing::DiscountCodes::ValidateCode.call(
      code: code,
      operator: current_tenant,
      location: current_location,
      product_type: 'day_pass',
    )

    if result.success?
      dc = result.discount_code
      # Only surface codes that apply to day passes (or everything).
      unless %w[day_pass all].include?(dc.applies_to)
        return render json: { type: 'invalid', valid: false, error: "This code can't be used on day passes." }, status: :unprocessable_entity
      end

      is_free = dc.discount_type == 'percent_off' && dc.discount_value.to_i >= 100

      render json: {
        type: is_free ? 'free' : 'discount',
        valid: true,
        code: dc.code,
        discount_type: dc.discount_type,
        discount_value: dc.discount_value,
        description: dc.try(:description),
        display: dc.discount_display,
        message: (is_free ? 'This code covers a day pass — pick one below to redeem.' : 'Discount applied — it\'ll be used at purchase.'),
      }
    else
      render json: { type: 'invalid', valid: false, error: result.message || 'Invalid code' }, status: :unprocessable_entity
    end
  end
end
