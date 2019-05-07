class Operator::DayPassesController < Operator::BaseController
  include DayPassesHelper

  def index
    find_day_passes
    authorize @day_passes
    background_image
  end

  def new
    @day_pass = DayPass.new
    authorize @day_pass
    background_image
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
    background_image
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
