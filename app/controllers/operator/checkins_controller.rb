class Operator::CheckinsController < Operator::BaseController
  before_action :background_image

  def new
    @checkin = Checkin.new
    include_stripe
  end

  def create
    token = params[:stripeToken]
    out_of_band = params[:out_of_band]

    if token && !(out_of_band || current_user.out_of_band)
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
      turbolinks_redirect(home_path, action: "replace")
    else
      flash[:error] = result.message
      turbolinks_redirect(referrer_or_root, action: "replace")
    end
  end

  def destroy
    @checkin = Checkin.find(params[:id])
    authorize @checkin

    result = Checkins::Checkout.call(checkin: @checkin)

    if result.success?
      flash[:success] = "You've checked out."
      turbolinks_redirect(home_path, action: "replace")
    else
      flash[:error] = result.message
      turbolinks_redirect(referrer_or_root, action: "replace")
    end
  end
end