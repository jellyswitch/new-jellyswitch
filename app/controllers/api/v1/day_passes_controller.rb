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
    code = params[:code]&.strip
    return render_error('Please enter a code') if code.blank?

    day_pass_code = DayPassCode.find_by(code: code, operator: current_tenant)
    return render_error('Invalid code') unless day_pass_code
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
      render json: { success: true, message: "Day pass redeemed!" }, status: :created
    else
      render_error(day_pass.errors.full_messages.first)
    end
  end
end
