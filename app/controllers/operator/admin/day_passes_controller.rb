
class Operator::Admin::DayPassesController < Operator::BaseController
  include DayPassesHelper

  def new
    authorize DayPass.new
    @user = current_location.users.find(params[:user_id])
  end

  def create
    authorize DayPass.new

    user = User.find(day_pass_params[:user_id])
    token = params[:stripeToken]
    out_of_band = pay_by_check_params[:out_of_band]
    # comp: staff adds the pass on the house — no Stripe invoice, no charge,
    # pass flagged complimentary (reports already exclude those from revenue).
    # DayPassPolicy#create? also admits members with billing enabled, so the
    # flag is gated server-side on staff — same predicate as the web comp
    # booking (#671). A member posting comp=1 just buys the pass normally.
    comp = staff? && params.dig(:day_pass, :comp) == "1"

    result = DayPassInteractorFactory.for(token, current_tenant).call(
      params: day_pass_params,
      user_id: user.id,
      token: token,
      operator: current_tenant,
      out_of_band: out_of_band,
      location: current_location,
      comp: comp
    )

    @day_pass = result.day_pass

    if result.success?
      flash[:success] = "Day pass added."
      # TODO: check if we need to inject tracking pixels here
      turbo_redirect(user_path(@day_pass.user), action: "replace")
    else
      flash[:error] = result.message
      turbo_redirect(user_path(user))
    end
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  private

  def staff?
    return false unless current_user.present?
    current_user.admin_of_location?(current_location) ||
      current_user.general_manager_of_location?(current_location) ||
      current_user.community_manager_of_location?(current_location)
  end

  def day_pass_params
    params.require(:day_pass).permit(:day_pass_type, :day, :user_id)
  end
end