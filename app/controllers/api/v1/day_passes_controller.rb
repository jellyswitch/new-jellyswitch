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
        quantity: t.quantity,
        included_meeting_minutes: t.try(:included_meeting_room_minutes),
      }
    }
  end

  def index
    passes = current_api_user.day_passes
      .where(operator: current_tenant)
      .includes(:day_pass_type, :invoice)
      .order(day: :desc)
      .limit(20)

    render json: passes.map { |dp|
      {
        id: dp.id,
        date: dp.day&.strftime("%B %e, %Y"),
        type_name: dp.day_pass_type&.name,
        price: dp.day_pass_type&.amount_in_cents,
        paid: dp.invoice&.paid? || false,
        complimentary: dp.complimentary,
      }
    }
  end

  def create
    day_pass_type = DayPassType.find(params[:day_pass_type_id])
    token = params[:stripe_token]
    discount_code = params[:discount_code]

    # Guardrails — only allow self-serve purchase of customer-facing,
    # paid day pass types. Free types (comp passes, discount-grants) are
    # created by the server (via GrantFreeDayPass / DayPassCode-style
    # flows) or by an admin through the admin endpoint, not by members
    # directly.
    # Hidden (visible:false) day pass types may be purchased only when the
    # request carries a matching access code — that's the whole point of the
    # access_code field. Without this bypass, the inline "have a code?" flow
    # from apply_code would surface the hidden pass id but create would still
    # reject it. The cross-check (code must match THIS pass) prevents using
    # one hidden pass's code to unlock a different hidden pass.
    return render_error('This day pass is not available.') unless day_pass_type.available
    unless day_pass_type.visible
      matches_access_code = discount_code.present? &&
        DayPassType.for_location(current_location).for_code(discount_code).exists?(id: day_pass_type.id)
      return render_error('This day pass is not available.') unless matches_access_code
    end
    return render_error('Free day passes cannot be purchased directly.') if day_pass_type.amount_in_cents.to_i <= 0

    # N-Pack: route to bundle flow (no date needed; passes are redeemed later)
    if day_pass_type.bundle?
      result = Billing::DayPassBundles::CreateBundle.call(
        user_id: current_api_user.id,
        operator: current_tenant,
        location: current_location,
        params: { day_pass_type: day_pass_type.id.to_s }
      )

      if result.success?
        b = result.day_pass_bundle
        render json: {
          success: true,
          id: b.id,
          passes_remaining: b.passes_remaining,
          day_pass_type_name: b.day_pass_type.name
        }, status: :created
      else
        render_error(result.message || "Unable to create day pass bundle")
      end
      return
    end

    # Single day pass — existing path unchanged
    date = params[:date].present? ? Date.parse(params[:date]) : Date.current

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

    # Apply discount code if provided. The same field accepts a DiscountCode
    # (percent / amount off) OR a DayPassType access code (e.g. "CoworkCafe").
    # We try DiscountCode first (case-insensitive via for_code scope). If that
    # fails AND it matches a DayPassType OTHER than the one being purchased,
    # surface a structured error so the mobile client can redirect the user.
    # If it matches THE SAME pass being purchased, the code is the access key
    # that unlocked this hidden pass — not a coupon — so we accept it silently.
    if discount_code.present?
      dc = DiscountCode.for_location(current_location).for_code(discount_code).first
      if dc&.active?
        interactor_params[:discount_code] = dc
      else
        dpt = DayPassType.for_location(current_location).for_code(discount_code).first
        if dpt && dpt.id != day_pass_type.id
          return render json: {
            success: false,
            error: "This code unlocks #{dpt.name} (#{ActionController::Base.helpers.number_to_currency(dpt.amount_in_cents.to_i / 100.0)}). Please switch to that day pass to use the code.",
            day_pass_type_id: dpt.id,
            day_pass_type_name: dpt.name,
          }, status: :unprocessable_entity
        end
      end
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
      # Fallback: maybe it's a DayPassType access code (e.g. "CoworkCafe")
      # rather than a coupon. Return the matching day pass so the mobile
      # client can route the user there.
      dpt = DayPassType.for_location(current_location).for_code(code).first
      if dpt
        render json: {
          type: 'day_pass_type',
          valid: true,
          code: code,
          day_pass_type_id: dpt.id,
          day_pass_type_name: dpt.name,
          amount_in_cents: dpt.amount_in_cents,
          message: "Code unlocks #{dpt.name} — #{ActionController::Base.helpers.number_to_currency(dpt.amount_in_cents.to_i / 100.0)}.",
        }
      else
        render json: { type: 'invalid', valid: false, error: result.message || 'Invalid code' }, status: :unprocessable_entity
      end
    end
  end
end
