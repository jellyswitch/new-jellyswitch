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
        day: dp.day&.iso8601, # ISO 'YYYY-MM-DD' — clients compare on this, NOT the formatted `date`
        type_name: dp.day_pass_type&.name,
        price: dp.day_pass_type&.amount_in_cents,
        paid: dp.invoice&.paid? || false,
        complimentary: dp.complimentary,
        can_reschedule: dp.reschedulable?,
      }
    }
  end

  def create
    day_pass_type = DayPassType.find(params[:day_pass_type_id])
    token = params[:stripe_token]
    discount_code = params[:discount_code]

    # Guardrails — only allow self-serve purchase of customer-facing,
    # paid day pass types. Free types (comp passes, discount-grants) are
    # created by the server (DayPassCode-style flows) or by an admin through
    # the admin endpoint, not by members directly.
    # Hidden (visible:false) day pass types may be purchased only when the
    # request carries a matching access code — that's the whole point of the
    # access_code field. Without this bypass, the inline "have a code?" flow
    # from apply_code would surface the hidden pass id but create would still
    # reject it. The cross-check (code must match THIS pass) prevents using
    # one hidden pass's code to unlock a different hidden pass.
    return render_error('This day pass is not available.') unless day_pass_type.available
    unless day_pass_type.visible
      return render_error('This day pass is not available.') unless access_code_matches?(day_pass_type, discount_code)
    end
    return render_error('Free day passes cannot be purchased directly.') if day_pass_type.amount_in_cents.to_i <= 0

    # N-Pack: route to bundle flow (no date needed; passes are redeemed later)
    if day_pass_type.bundle?
      # Discount codes don't apply to bundles. But a HIDDEN bundle is unlocked by
      # its own access code (threaded in as discount_code — the visible-gate above
      # requires it), which is the access key, not a coupon. Reject only a code
      # that is NOT this bundle's own access code, else a legitimate code-holder
      # could never buy a hidden N-Pack. Mirrors the web create_bundle guard.
      if discount_code.present? && !access_code_matches?(day_pass_type, discount_code)
        return render_error("Discount codes can't be applied to day pass bundles.")
      end

      bundle_interactor = token.present? ?
        Billing::DayPassBundles::UpdatePaymentAndCreateBundle :
        Billing::DayPassBundles::CreateBundle

      result = bundle_interactor.call(
        user_id: current_api_user.id,
        operator: current_tenant,
        location: current_location,
        token: token,
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

    # Daily cap (physical capacity — e.g. 2 day offices). Member self-serve
    # only: staff/admin paths and door burns are intentionally ungated, though
    # their rows still count toward the tally. See
    # docs/superpowers/specs/2026-07-12-day-pass-daily-limit-design.md.
    if day_pass_type.daily_limit_reached?(day: date, location: current_location)
      return render_error("#{day_pass_type.name.pluralize} are fully booked for #{date.strftime('%B %e')}. Try another day.")
    end

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
      # Validate as a real day-pass discount code — scope (applies_to day_pass),
      # expiry, and redemption cap — not just the `active` flag. The old
      # dc&.active? check let a member apply a membership-only / meeting-room-
      # only, expired, or maxed-out code (up to 100%-off = free pass) to a day
      # pass. Mirrors the web's Billing::DiscountCodes::ValidateCode.
      validate = Billing::DiscountCodes::ValidateCode.call(
        code: discount_code,
        location: current_location,
        product_type: "day_pass",
      )
      if validate.success?
        interactor_params[:discount_code] = validate.discount_code
      else
        # Not a valid coupon — it may instead be a DayPassType ACCESS code. If it
        # unlocks a DIFFERENT hidden pass, tell the client to switch; if it
        # matches THIS pass it's the access key (already validated above) so the
        # purchase proceeds at full price without applying it as a coupon.
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

  # POST /api/v1/day_passes/schedule
  # Member schedules one or more future dates from their bundle.
  # Calls ScheduleDays (all-or-nothing) and returns the confirmed dates.
  def schedule
    result = Billing::DayPassBundles::ScheduleDays.call(
      user: current_api_user, location: current_location,
      dates: Array(params[:dates]), performed_by: current_api_user,
      enforce_daily_limit: true)

    case result.outcome
    when :scheduled
      render json: {
        status: "scheduled",
        scheduled_days: result.day_passes.map { |dp| dp.day.iso8601 },
        passes_remaining: remaining_bundle_passes,
      }
    when :sold_out
      render_error("#{result.day_pass_type.name.pluralize} are fully booked for #{result.failed_date.strftime('%B %e')}. Try another day.")
    when :already_covered
      render_error("You're already set for #{result.failed_date.strftime('%B %e')}.")
    when :invalid_date
      render_error("That date can't be scheduled.")
    else # :no_bundle
      render_error("You don't have enough day passes left.")
    end
  end

  # GET /api/v1/day_passes/scheduled_days
  # Lists upcoming bundle-sourced passes for the current member at their location.
  def scheduled_days
    tz    = ActiveSupport::TimeZone[current_location&.time_zone.presence || "UTC"]
    today = Time.current.in_time_zone(tz).to_date
    passes = current_api_user.day_passes.bundle_sourced
               .for_location(current_location).where("day > ?", today).order(:day)
    render json: passes.map { |dp| { id: dp.id, day: dp.day.iso8601, date: dp.day.strftime("%B %e, %Y") } }
  end

  # POST /api/v1/day_passes/:id/cancel_scheduled
  # Cancels a future bundle-sourced scheduled pass, restoring it to the bundle.
  # Scoped to the current_api_user so members cannot cancel each other's passes.
  def cancel_scheduled
    day_pass = current_api_user.day_passes.find(params[:id])
    result = Billing::DayPassBundles::CancelScheduledDay.call(day_pass: day_pass, performed_by: current_api_user)
    case result.outcome
    when :cancelled
      render json: { status: "cancelled", passes_remaining: remaining_bundle_passes }
    when :too_late
      render_error("That day has already started — it can't be cancelled.")
    else
      render_error("That scheduled day couldn't be found.")
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Not found" }, status: :not_found
  end

  # PATCH /api/v1/day_passes/:id/reschedule
  # Moves an UNUSED pass (no entry recorded on its day) to today or any
  # future date — even a pass whose day already slipped by. Works for
  # purchased and bundle-sourced passes alike: the row keeps its id and
  # invoice, only `day` changes. Scoped to current_api_user.
  def reschedule
    day_pass = current_api_user.day_passes.where(operator: current_tenant).find(params[:id])
    return render_error("That pass was already used — it can't be moved.") unless day_pass.reschedulable?

    new_day = begin
      Date.iso8601(params[:day].to_s)
    rescue ArgumentError, TypeError
      nil
    end
    return render_error("Please pick a valid date.") unless new_day

    tz    = ActiveSupport::TimeZone[day_pass.location&.time_zone.presence || "UTC"]
    today = Time.current.in_time_zone(tz).to_date
    return render_error("Passes can only be moved to today or a future date.") if new_day < today

    # Daily cap on the TARGET day. Skipped when the pass isn't actually
    # changing days — its own row would otherwise count against itself.
    if new_day != day_pass.day &&
       day_pass.day_pass_type&.daily_limit_reached?(day: new_day, location: day_pass.location)
      return render_error("#{day_pass.day_pass_type.name.pluralize} are fully booked for #{new_day.strftime('%B %e')}. Try another day.")
    end

    day_pass.update!(day: new_day)
    render json: { status: "rescheduled", id: day_pass.id, day: day_pass.day.iso8601, date: day_pass.day.strftime("%B %e, %Y") }
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Not found" }, status: :not_found
  end

  # POST /api/v1/day_passes/redeem_today
  # Member self-redeems one bundle pass to get access today without tapping a door.
  # Reuses ConsumeOnEntry (idempotent, same logic as door entry) and maps its
  # outcome to a clear API response so the app can show a meaningful message.
  #
  # Outcomes:
  #   redeemed          → burned one pass; today now covered    → 200 { status: "redeemed", passes_remaining: N }
  #   already_covered   → already had access for today (sub / lease / reservation
  #                        / non-bundle day pass / bundle already burned)
  #                                                              → 200 { status: "already_active_today" }
  #   no_bundle         → no active bundle and no other coverage → 422 render_error
  #   nil               → NoPassesRemaining rescued inside interactor (race)  → 422 render_error
  def redeem_today
    result = Billing::DayPassBundles::ConsumeOnEntry.call(
      user:     current_api_user,
      location: current_location,
    )

    case result.outcome
    when :redeemed
      bundle = current_api_user.day_pass_bundles.active.where(location: current_location).first
      render json: {
        status:          "redeemed",
        passes_remaining: bundle&.passes_remaining,
      }
    when :already_covered
      render json: { status: "already_active_today" }
    else
      # :no_bundle or nil (NoPassesRemaining race)
      render_error("You don't have any day passes left.")
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

  private

  # True when the request carries this day-pass-type's own access code — the key
  # that unlocks a hidden (visible:false) type. Shared by the visible-gate and
  # the bundle branch so a hidden bundle's access code isn't mistaken for a
  # (rejected) coupon. Mirrors the web Operator::DayPassesController guard.
  def access_code_matches?(day_pass_type, code)
    code.present? &&
      DayPassType.for_location(current_location).for_code(code).exists?(id: day_pass_type.id)
  end

  def remaining_bundle_passes
    current_api_user.day_pass_bundles.active.where(location: current_location).sum(:passes_remaining)
  end
end
