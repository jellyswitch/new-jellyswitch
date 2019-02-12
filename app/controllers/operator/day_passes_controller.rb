class Operator::DayPassesController < Operator::BaseController
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
    
    if admin?
      result = CreateDayPass.call(
        params: admin_day_pass_params,
        user_id: admin_day_pass_params[:day_pass][:user_id],
        token: params[:stripeToken],
        operator: current_tenant
      )
    else
      result = CreateDayPass.call(
        params: day_pass_params,
        user_id: current_user.id,
        token: params[:stripeToken],
        operator: current_tenant
      )
    end

    @day_pass = result.day_pass

    if result.success?
      flash[:success] = "Welcome to #{current_tenant.name}!"
      redirect_to home_path
    else
      flash[:error] = result.message
      redirect_to root_path
    end
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
    params.require(:day_pass).permit(:day)
  end

  def admin_day_pass_params
    params.require(:day_pass).permit(:day, :user_id)
  end
end