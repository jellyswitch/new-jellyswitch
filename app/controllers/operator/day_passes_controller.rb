class Operator::DayPassesController < Operator::ApplicationController
  def index
    find_day_passes
    authorize @day_passes
  end

  def new
    @day_pass = DayPass.new
    authorize @day_pass
    background_image
    include_stripe
  end

  def create
    if admin?
      @day_pass = new_day_pass(admin_day_pass_params)
    else
      @day_pass = new_day_pass(day_pass_params)
    end

    authorize @day_pass
    
    token = params[:stripeToken]
    current_user.ensure_stripe_customer(token)
    if @day_pass.save 
      flash[:success] = "Welcome to #{current_tenant.name}!"
      redirect_to root_path
    else
      flash[:error] = "An error occurred."
      render :new
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

  def new_day_pass(params)
    day_pass = DayPass.new(params)
    day_pass.user = current_user unless admin?
    day_pass
  end
end