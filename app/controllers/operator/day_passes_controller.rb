class Operator::DayPassesController < Operator::BaseController
  include DayPassesHelper
  before_action :background_image

  def index
    find_day_passes
    authorize @day_passes
  end

  def new
    @day_pass = DayPass.new
    authorize @day_pass
    include_stripe
  end

  def create
    authorize DayPass.new

    token = params[:stripeToken]
    out_of_band = pay_by_check_params[:out_of_band]

    if token && !(out_of_band || current_user.out_of_band)
      result = Billing::DayPasses::UpdatePaymentAndCreateDayPass.call(
        params: day_pass_params,
        user_id: current_user.id,
        token: token,
        operator: current_tenant,
        out_of_band: out_of_band
      )
    else
      result = Billing::DayPasses::CreateDayPass.call(
        params: day_pass_params,
        user_id: current_user.id,
        token: token,
        operator: current_tenant,
        out_of_band: out_of_band
      )
    end

    @day_pass = result.day_pass

    if result.success?
      flash[:success] = "Welcome to #{current_tenant.name}!"
      turbolinks_redirect(home_path)
    else
      flash[:error] = result.message
      turbolinks_redirect(new_day_pass_path)
    end
  rescue => e
    Rollbar.error(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbolinks_redirect(referrer_or_root)
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
      operator: current_tenant
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
          params: {
            day: Time.current,
            day_pass_type: result.day_pass_type.id
          }
        )
        if result2.success?
          flash[:success] = "Day Pass redeemed!"
          turbolinks_redirect(home_path, action: "replace")
        else
          flash[:error] = result.message
          turbolinks_redirect(code_day_passes_path, action: "replace")
        end
      else
        raise "Not a free day pass"
        # todo: create a page where they can click "purchase" for the specific day pass
        # clone day_passes#new but with a hidden field with hidden day pass type instead of dropdown
      end
    else
      flash[:error] = result.message
      turbolinks_redirect(code_day_passes_path, action: "replace")
    end
  end

  private

  def find_day_passes
    @day_passes = DayPass.order('created_at DESC')
  end

  def find_day_pass(key=:id)
    @day_pass = DayPass.find(params[:id])
  end

  def day_pass_params
    params.require(:day_pass).permit(:day, :day_pass_type)
  end
end
