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

  def redeem
    apply_code_action(require_pass_code: true)
  end

  # POST /api/v1/day_passes/apply_code
  # Unified code entry: tries a DayPassCode (comp pass) first, then a
  # DiscountCode (% or $ off at purchase). Returns a shape the client
  # uses to either celebrate + stop, or to carry the discount into
  # the next purchase call.
  def apply_code
    apply_code_action(require_pass_code: false)
  end

  private

  def apply_code_action(require_pass_code:)
    code = params[:code]&.strip
    return render_error('Please enter a code') if code.blank?

    # 1) Try single-use day pass code (grants a free pass).
    day_pass_code = DayPassCode.find_by(code: code, operator: current_tenant)
    if day_pass_code
      return render_error('This code has already been used') if day_pass_code.redeemed?

      day_pass = DayPass.create(
        user: current_api_user,
        billable: current_api_user,
        day_pass_type: day_pass_code.day_pass_type,
        day: Date.current,
        operator: current_tenant,
        location: current_location,
        complimentary: true,
      )

      if day_pass.persisted?
        day_pass_code.update(redeemed: true, redeemed_by: current_api_user)
        return render json: {
          type: 'redeemed',
          success: true,
          message: 'Day pass redeemed!',
          day_pass: { id: day_pass.id, day: day_pass.day, type_name: day_pass_code.day_pass_type&.name },
        }, status: :created
      else
        return render_error(day_pass.errors.full_messages.first)
      end
    end

    return render_error('Invalid code') if require_pass_code

    # 2) Try a discount code (percentage / amount off at purchase).
    result = Billing::DiscountCodes::ValidateCode.call(
      code: code,
      operator: current_tenant,
    )

    if result.success?
      dc = result.discount_code
      render json: {
        type: 'discount',
        valid: true,
        code: dc.code,
        discount_type: dc.discount_type,
        discount_value: dc.discount_value,
        description: dc.try(:description),
        message: 'Discount applied — it\'ll be used at purchase.',
      }
    else
      render json: { type: 'invalid', valid: false, error: result.message || 'Invalid code' }, status: :unprocessable_entity
    end
  end
end
