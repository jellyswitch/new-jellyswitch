
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

    # N-Pack SKUs are prepaid bundles, not single dated day passes. The web
    # checkout below (date picker, duplicate-by-date guard, single-pass
    # interactor) only models a single pass — so without this branch, buying a
    # 2-Pack here silently minted ONE dated DayPass and charged the full bundle
    # price (two real Cowork Tahoe customers hit exactly this). Route bundle
    # SKUs to the same flow the mobile API uses; the picked date is irrelevant
    # because bundle passes are redeemed later.
    bundle_type = current_location&.day_pass_types&.find_by(id: params.dig(:day_pass, :day_pass_type))
    return create_bundle(bundle_type) if bundle_type&.bundle?

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
          turbo_redirect(redeem_paid_day_passes_path(
            code: params[:discount_code],
            day_pass_type_id: dpt_result.day_pass_type.id
          ))
          return
        end

        flash[:error] = validate_result.message
        turbo_redirect(new_day_pass_path)
        return
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
        flash[:success] = "Welcome to #{current_tenant.name}!"
      else
        flash[:success] = "Thanks! Your day pass will be available on #{short_date(@day_pass.day)}."
      end
      flash.keep
      session[:should_track_pixels] = true
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
      @day_pass = DayPass.new
      include_stripe
    else
      flash[:error] = "No such code."
      turbo_redirect(code_day_passes_path, action: "replace")
    end
  end

  # POST /day_passes/redeem_today
  # Member self-redeems one bundle pass for "today" from the web — parity with
  # the mobile API's redeem_today, through the SAME single authority
  # (Billing::DayPassBundles::ConsumeOnEntry): today-only, idempotent, and a
  # no-op when other coverage already grants access.
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

  private

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
    if params[:discount_code].present?
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
      flash[:success] = "Thanks! #{bundle.passes_remaining} day passes added to your account."
      flash.keep
      session[:should_track_pixels] = true
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
