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

    day_pass = DayPass.new(
      user: current_api_user,
      billable: current_api_user,
      day_pass_type: day_pass_type,
      day: date,
      operator: current_tenant,
      location: current_location,
    )

    # If paid type and user provides a new card token, update payment first
    if day_pass_type.amount_in_cents > 0 && params[:stripe_token].present?
      Billing::Payment::UpdateUserPayment.call(
        user: current_api_user,
        token: params[:stripe_token],
        operator: current_tenant,
        location: current_location,
      )
    end

    if day_pass.save
      # Charge via Stripe if paid type
      if day_pass_type.amount_in_cents > 0
        begin
          Billing::DayPasses::ChargeDayPass.call(
            day_pass: day_pass,
            user: current_api_user,
            location: current_location,
            operator: current_tenant,
          )
        rescue => e
          day_pass.destroy
          return render_error("Payment failed: #{e.message}")
        end
      end
      render json: { success: true, id: day_pass.id, date: day_pass.day.strftime("%B %e, %Y") }, status: :created
    else
      render_error(day_pass.errors.full_messages.first)
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
