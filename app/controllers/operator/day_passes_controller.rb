
class Operator::DayPassesController < Operator::BaseController
  include DayPassesHelper
  before_action :background_image
  before_action :require_authentication, only: :redeem_today

  def index
    find_day_passes
    return if performed?
    authorize @day_passes
  end

  def new
    @day_pass = DayPass.new
    find_day_pass_type
    return if performed?
    authorize @day_pass
    include_stripe
  end

  def create
    authorize DayPass.new

    # Members may only self-purchase a customer-facing, PAID day pass / bundle:
    # available (not a retired SKU) and priced > $0. Free/comp types are admin-
    # or code-granted — a $0 self-mint would be free building access — so they
    # aren't self-served here. Hidden (visible:false) types are reached via the
    # redeem_paid access-code flow and require a matching code (threaded through
    # the checkout as discount_code). Mirrors the mobile API guardrails.
    day_pass_type = current_location&.day_pass_types&.find_by(id: params.dig(:day_pass, :day_pass_type))
    return if reject_unpurchasable_day_pass_type(day_pass_type)

    # N-Pack SKUs are prepaid bundles, not single dated day passes. The web
    # checkout below (date picker, duplicate-by-date guard, single-pass
    # interactor) only models a single pass — so without this branch, buying a
    # 2-Pack here silently minted ONE dated DayPass and charged the full bundle
    # price (two real Cowork Tahoe customers hit exactly this). Route bundle
    # SKUs to the same flow the mobile API uses; the picked date is irrelevant
    # because bundle passes are redeemed later.
    return create_bundle(day_pass_type) if day_pass_type&.bundle?

    # Duplicate-purchase guard: when the member already has a day pass for
    # the same date at this location, render an interstitial confirm page
    # rather than silently charging again. They may legitimately be buying
    # a second pass for a guest — the confirm step keeps that intentional
    # while still catching the accidental double-submits that previously
    # accumulated extra Stripe invoices and decline attempts.
    #
    # Parse the date directly from the multi-parameter form fields rather
    # than building a DayPass — DayPass.new would coerce the day_pass_type
    # string into the association and raise AssociationTypeMismatch.
    prospective_day = begin
      Date.new(
        params.dig(:day_pass, :"day(1i)").to_i,
        params.dig(:day_pass, :"day(2i)").to_i,
        params.dig(:day_pass, :"day(3i)").to_i,
      )
    rescue ArgumentError, TypeError
      nil
    end

    # A crafted POST can send a plain-string day_pass[day] instead of the
    # form's multiparameter fields; ActiveRecord would cast it downstream in
    # SaveDayPass, so the gate (and the duplicate guard below) must see the
    # same value or a hand-rolled request could buy onto a sold-out day.
    prospective_day ||= ActiveModel::Type::Date.new.cast(params.dig(:day_pass, :day))

    # Self-serve purchase window (DayPass::MAX_ADVANCE_DAYS). The form's year
    # dropdown made "today's date, NEXT year" a one-notch mis-tap that charged
    # real money for a pass the buyer would never see.
    if prospective_day
      tz = ActiveSupport::TimeZone[current_location&.time_zone.presence || "UTC"]
      today = Time.current.in_time_zone(tz).to_date
      if prospective_day < today
        flash[:error] = "That date has already passed — double-check the date."
        turbo_redirect(new_day_pass_path(day_pass_type_id: day_pass_type&.id))
        return
      elsif prospective_day > today + DayPass::MAX_ADVANCE_DAYS
        flash[:error] = "Day passes can be scheduled up to #{DayPass::MAX_ADVANCE_DAYS} days ahead — double-check the date (including the year)."
        turbo_redirect(new_day_pass_path(day_pass_type_id: day_pass_type&.id))
        return
      end
    end

    # Daily cap (physical capacity — e.g. 2 day offices). Member self-serve
    # only: the admin add/comp flow (Operator::Admin::DayPassesController) is
    # intentionally ungated, though its rows still count. Checked before the
    # duplicate-purchase confirm — a sold-out day is sold out regardless.
    if prospective_day && day_pass_type&.daily_limit_reached?(day: prospective_day, location: current_location)
      message = "#{day_pass_type.name.pluralize} are fully booked for #{short_date(prospective_day)}. Try another day."
      # Point the buyer at an immediate alternative instead of a dead end
      # (mirrors the mobile API's day-office sold-out fallback, ADR 0026) —
      # never an office or bundle type, and nil when nothing else qualifies.
      # suggested.id != day_pass_type.id: when the sold-out type is itself
      # the only qualifying candidate (a standard type with no sibling),
      # suggested_standard_for has nothing else to offer but itself — never
      # echo the same sold-out type back as its own "alternative".
      suggested = DayPassType.suggested_standard_for(current_location)
      message += " A #{suggested.name} is available instead." if suggested && suggested.id != day_pass_type.id
      # Turned-away Day Office demand goes to the management feed (parity with
      # the mobile API's render_day_office_sold_out). Best-effort.
      if day_pass_type.day_office?
        DayOffices::RecordSoldOut.call(
          user: current_user, day_pass_type: day_pass_type, day: prospective_day,
          location: current_location, operator: current_tenant,
        )
      end
      flash[:error] = message
      turbo_redirect(new_day_pass_path(day_pass_type_id: day_pass_type.id))
      return
    end

    if prospective_day &&
       params[:confirm_duplicate].to_s != "1" &&
       DayPass.where(user_id: current_user.id, day: prospective_day, location_id: current_location.id).exists?
      @prospective_day = prospective_day
      @day_pass_type_id = params.dig(:day_pass, :day_pass_type)
      render :confirm_duplicate and return
    end

    token = params[:stripeToken]
    out_of_band = pay_by_check_params[:out_of_band]

    # Validate discount code if provided.
    # The inline "discount code" field accepts BOTH a DiscountCode (percent /
    # amount off) AND a DayPassType access code (e.g. "CoworkCafe" — unlocks a
    # hidden $10 Cafe Hour Pass). If DiscountCode lookup fails, we fall back to
    # DayPassType.for_code. A match there means the customer typed an access
    # code, not a coupon — we redirect them to that day-pass-type's checkout
    # instead of returning an unhelpful "Invalid discount code" error.
    discount_code = nil
    if params[:discount_code].present?
      validate_result = Billing::DiscountCodes::ValidateCode.call(
        code: params[:discount_code],
        location: current_location,
        product_type: "day_pass"
      )
      if validate_result.success?
        discount_code = validate_result.discount_code
      else
        dpt_result = Billing::DayPasses::RedeemCode.call(
          code: params[:discount_code],
          operator: current_tenant,
          location: current_location
        )
        if dpt_result.success?
          # The code is a DayPassType access code, not a coupon. If it unlocks a
          # DIFFERENT type than the one being purchased, route the buyer to that
          # type's checkout (the existing "surface the hidden pass" behavior). If
          # it matches THE SAME type, the redeem_paid checkout threaded it into
          # this POST to satisfy the hidden-pass guard — let the purchase proceed
          # at full price without applying it as a discount. Mirrors the mobile API.
          if dpt_result.day_pass_type.id != day_pass_type&.id
            turbo_redirect(redeem_paid_day_passes_path(
              code: params[:discount_code],
              day_pass_type_id: dpt_result.day_pass_type.id
            ))
            return
          end
        else
          flash[:error] = validate_result.message
          turbo_redirect(new_day_pass_path)
          return
        end
      end
    end

    result = DayPassInteractorFactory.for(token, current_tenant).call(
      params: day_pass_params,
      user_id: current_user.id,
      token: token,
      operator: current_tenant,
      out_of_band: out_of_band,
      location: current_location,
      discount_code: discount_code
    )
    @day_pass = result.day_pass

    if result.success?
      if @day_pass.today?
        flash[:success] = append_email_handoff("Welcome to #{current_tenant.name}!")
      else
        flash[:success] = append_email_handoff("Thanks! Your day pass will be available on #{short_date(@day_pass.day)}.")
      end
      flash.keep
      track_conversion("day_pass",
                       product_name: @day_pass.day_pass_type&.name,
                       amount_in_cents: @day_pass.day_pass_type&.amount_in_cents,
                       transaction_id: "dp_#{@day_pass.id}")
      # An unapproved member just buying their way in during onboarding should
      # land on the "You're almost in!" confirmation (/wait) so the purchase is
      # clearly acknowledged — not back on home_path, which resolves to the
      # /choose Welcome screen and reads as "back to the purchase options".
      # Already-approved members still go straight home.
      turbo_redirect(approved? ? home_path : wait_path)
    else
      flash[:error] = result.message
      turbo_redirect(new_day_pass_path(day_pass_type_id: params.dig(:day_pass, :day_pass_type)))
    end
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  def show
    find_day_pass
    authorize @day_pass
  end

  def code
    authorize DayPass.new
  end

  def redeem_code
    result = Billing::DayPasses::RedeemCode.call(
      code: params[:code],
      operator: current_tenant,
      location: current_location
    )

    if result.success?
      if result.day_pass_type.free?
        result2 = Billing::DayPasses::RedeemFreeDayPass.call(
          user: current_user,
          token: nil,
          day_pass: nil,
          out_of_band: current_user.out_of_band,
          user_id: current_user.id,
          operator: current_tenant,
          location: current_location, # this might cause issues later, check if there is a bug
          params: {
            day: Time.current,
            day_pass_type: result.day_pass_type.id
          }
        )
        if result2.success?
          flash[:success] = "Day Pass redeemed!"
          turbo_redirect(home_path, action: "replace")
        else
          flash[:error] = result.message
          turbo_redirect(code_day_passes_path, action: "replace")
        end
      else
        turbo_redirect(redeem_paid_day_passes_path(code: params[:code], day_pass_type_id: result.day_pass_type_id ))
      end
    else
      flash[:error] = result.message
      turbo_redirect(code_day_passes_path, action: "replace")
    end
  end

  def redeem_paid
    result = Billing::DayPasses::RedeemCode.call(
      code: params[:code],
      operator: current_tenant,
      location: current_location
    )

    if result.success?
      @day_pass_type = result.day_pass_type
      # Thread the validated access code into the checkout form so the purchase
      # POST carries it — the hidden-pass guard on #create requires a code that
      # matches this (visible:false) type. Without it, a legitimate code-holder
      # would be blocked at purchase.
      @access_code = params[:code]
      @day_pass = DayPass.new
      include_stripe
    else
      flash[:error] = "No such code."
      turbo_redirect(code_day_passes_path, action: "replace")
    end
  end

  # POST /day_passes/redeem_today
  # Member self-redeems one bundle pass for "today" from the web. Always
  # routes through Billing::DayPassBundles::ConsumeOnEntry: today-only,
  # idempotent, and a no-op when other coverage already grants access.
  #
  # Day Office bundles (ADR 0026) need no special-casing here: as of Task 11
  # ConsumeOnEntry allocates a pool room itself on the office branch, and
  # notifies the member either way — with the room when one was free, or with
  # the walk-in "your pass still works, see staff" message (plus a staff alert)
  # when the pool was full. The divergence from the mobile API's redeem_today,
  # which routes an office bundle through ScheduleDay, is now only about which
  # idempotency window applies (business day here, calendar date there).
  #
  # ADR 0017: a redemption mints today's DayPass (the right to be present) but
  # does NOT open a door — so the success copy hands the member off to the app.
  def redeem_today
    result = Billing::DayPassBundles::ConsumeOnEntry.call(
      user:     current_user,
      location: current_location,
    )

    case result.outcome
    when :redeemed
      remaining = current_user.day_pass_bundles.active.where(location: current_location).sum(:passes_remaining)
      flash[:success] = "You're set for today — #{remaining} #{'pass'.pluralize(remaining)} left. Open the app to unlock the door."
    when :already_covered
      flash[:success] = "You're already set for today."
    else
      flash[:error] = "You don't have any day passes left."
    end

    turbo_redirect(home_path)
  end

  # PATCH /day_passes/:id/reschedule — staff move a member's UNUSED pass to
  # today or a future date (policy: admin/CM/GM only). Same rules as the
  # member-facing mobile endpoint; the pass keeps its id and invoice.
  def reschedule
    @day_pass = DayPass.where(operator: current_tenant).find(params[:id])
    authorize @day_pass

    new_day = begin
      Date.iso8601(params[:day].to_s)
    rescue ArgumentError, TypeError
      nil
    end

    tz    = ActiveSupport::TimeZone[@day_pass.location&.time_zone.presence || "UTC"] || Time.zone
    today = Time.current.in_time_zone(tz).to_date

    if !@day_pass.reschedulable?
      flash[:error] = "That pass was already used — it can't be moved."
    elsif new_day.nil? || new_day < today
      flash[:error] = "Pick today or a future date."
    else
      old_day = @day_pass.day
      if @day_pass.day_office? && new_day != @day_pass.day
        move = DayOffices::MoveHold.call(day_pass: @day_pass, new_day: new_day)
        unless move.ok?
          flash[:error] = "#{@day_pass.day_pass_type.name.pluralize} are fully booked for #{new_day.strftime('%B %e')}. Try another day."
          return turbo_redirect(user_admin_day_passes_path(@day_pass.user))
        end
      else
        @day_pass.update!(day: new_day)
      end
      UserMailer.day_pass_rescheduled(@day_pass.id, old_day).deliver_later if @day_pass.day != old_day
      flash[:success] = "Day pass moved to #{@day_pass.pretty_day}."
    end

    turbo_redirect(user_admin_day_passes_path(@day_pass.user))
  end

  private

  # Members may only self-purchase a customer-facing, PAID day pass / bundle.
  # Rejects a retired (available:false) SKU and a free ($0) type — a member
  # self-minting a $0 pass would get free building access with no charge or
  # code. Mirrors the mobile API guardrails; the web resolves the type from the
  # picker but a crafted POST can pass any operator-scoped id, so the check is
  # server-side. A nil type falls through (the interactor surfaces "Invalid day
  # pass type"). Returns true (and redirects) when the purchase must be blocked.
  #
  # Hidden (visible:false) types are unlocked by an access code. The redeem_paid
  # checkout threads that validated code into the purchase POST (as
  # discount_code), so we require it to match THIS type — otherwise a crafted
  # POST with no/wrong code could buy a hidden pass at its unlisted rate,
  # bypassing the access-code gate. Mirrors the mobile API guard.
  def reject_unpurchasable_day_pass_type(day_pass_type)
    return false if day_pass_type.nil?

    message =
      if !day_pass_type.available
        "This day pass is not available."
      elsif !day_pass_type.visible && !access_code_matches?(day_pass_type)
        "This day pass is not available."
      elsif day_pass_type.amount_in_cents.to_i <= 0
        "Free day passes can't be purchased directly."
      end
    return false unless message

    flash[:error] = message
    turbo_redirect(new_day_pass_path)
    true
  end

  # True when the request carries this day-pass-type's own access code. Gates
  # self-purchase of a hidden (visible:false) type to code-holders reaching it
  # through the redeem_paid flow, which threads the code in as discount_code.
  def access_code_matches?(day_pass_type)
    code = params[:discount_code]
    code.present? &&
      current_location.day_pass_types.for_code(code).exists?(id: day_pass_type.id)
  end

  def find_day_passes
    if current_location.nil?
      redirect_to root_path
      return
    end
    @day_passes = current_location.day_passes.order('created_at DESC')
  end

  def find_day_pass(key=:id)
    # Maybe needs to show at another location so we don't use current_location
    @day_pass = DayPass.find(params[:id])
  end

  # Mirrors the mobile API's bundle branch (Api::V1::DayPassesController#create):
  # one charge for the N-Pack SKU price, no DayPass minted — passes are burned
  # later at the door / via redeem. Token present => attach card first.
  def create_bundle(day_pass_type)
    # Discount codes don't apply to bundles. But a hidden bundle reached via the
    # redeem flow threads its own ACCESS code in as discount_code — that's the
    # access key, not a coupon, so let it through. Any other code is rejected.
    if params[:discount_code].present? && !access_code_matches?(day_pass_type)
      flash[:error] = "Discount codes can't be applied to day pass bundles."
      return turbo_redirect(new_day_pass_path(day_pass_type_id: day_pass_type.id))
    end

    token = params[:stripeToken]
    interactor = token.present? ?
      Billing::DayPassBundles::UpdatePaymentAndCreateBundle :
      Billing::DayPassBundles::CreateBundle

    result = interactor.call(
      user_id: current_user.id,
      operator: current_tenant,
      location: current_location,
      token: token,
      params: { day_pass_type: day_pass_type.id.to_s }
    )

    if result.success?
      bundle = result.day_pass_bundle
      flash[:success] = append_email_handoff("Thanks! #{bundle.passes_remaining} day passes added to your account.")
      flash.keep
      track_conversion("day_pass_bundle",
                       product_name: day_pass_type.name,
                       amount_in_cents: day_pass_type.amount_in_cents,
                       transaction_id: "dpb_#{bundle.id}")
      turbo_redirect(approved? ? home_path : wait_path)
    else
      flash[:error] = result.message
      turbo_redirect(new_day_pass_path(day_pass_type_id: day_pass_type.id))
    end
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  def day_pass_params
    params.require(:day_pass).permit(:day, :day_pass_type)
  end

  def find_day_pass_type(key=:day_pass_type_id)
    if current_location.nil?
      redirect_to root_path
      return
    end
    @day_pass_type = current_location.day_pass_types.find(params[key])
  end
end
