class Operator::CheckinsController < Operator::BaseController
  def create
    result = Checkins::CreateCheckin.call(
      user: current_user,
      operator: current_tenant,
      location: current_location
    )

    if result.success?
      turbolinks_redirect(home_path, action: "replace")
    else
      turbolinks_redirect(referrer_or_root, action: "replace")
    end
  end

  def destroy
    @checkin = Checkin.find(params[:id])

    result = Checkins::Checkout.call(checkin: @checkin)

    if result.success?
      flash[:success] = "You've checked out."
      turbolinks_redirect(home_path, action: "replace")
    end
  end
end