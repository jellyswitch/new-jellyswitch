
class Operator::CheckinsController < Operator::BaseController
  before_action :background_image

  def new
    @checkin = Checkin.new
    authorize @checkin
    include_stripe
  end

  def required
    @checkin = Checkin.new
    authorize @checkin
    include_stripe

    if current_location.blank?
      redirect_to root_path
    end
  end

  def create
    token = params[:stripeToken]
    out_of_band = params[:out_of_band]

    if token
      result = Checkins::UpdatePaymentAndCreateCheckin.call(
        user: current_user,
        operator: current_tenant,
        location: current_location,
        token: token,
        out_of_band: out_of_band
      )
    else
      result = Checkins::CreateCheckin.call(
        user: current_user,
        operator: current_tenant,
        location: current_location
      )
    end

    if result.success?
      turbo_redirect(home_path, action: "replace")
    else
      flash[:error] = result.message
      turbo_redirect(referrer_or_root, action: "replace")
    end
  end

  def index
    find_checkins
    authorize @checkins
  end

  def show
    find_checkin
    authorize @checkin
  end

  def destroy
    find_checkin
    authorize @checkin

    result = Checkins::Checkout.call(checkin: @checkin, datetime_out: Time.current)

    if result.success?
      flash[:success] = "You've checked out."
      turbo_redirect(home_path, action: "replace")
    else
      flash[:error] = result.message
      turbo_redirect(referrer_or_root, action: "replace")
    end
  end

  private

  def find_checkin
    @checkin = Checkin.find(params[:id])
  end

  def find_checkins
    @pagy, @checkins = pagy(current_location.checkins)
  end
end