class Operator::DayPassTypesController < Operator::BaseController
  before_action :find_day_pass_type, only: [:show, :edit, :update, :destroy]

  def index
    find_day_pass_types
    authorize @day_pass_types
  end

  def show
    authorize @day_pass_type
  end

  def new
    @day_pass_type = DayPassType.new
    authorize @day_pass_type
  end

  def edit
    authorize @day_pass_type
  end

  def create
    @day_pass_type = DayPassType.new(day_pass_type_params)
    authorize @day_pass_type

    if @day_pass_type.save
      redirect_to @day_pass_type, notice: 'Day pass type was successfully created.'
    else
      render :new
    end
  end

  def update
    authorize @day_pass_type
    
    if @day_pass_type.update(day_pass_type_params)
      redirect_to @day_pass_type, notice: 'Day pass type was successfully updated.'
    else
      render :edit
    end
  end

  def destroy
    authorize @day_pass_type
    @day_pass_type.update(available: false)

    redirect_to day_pass_types_url, notice: 'Day pass type was successfully archived.'
  end

  private
  
  def find_day_pass_type(key=:id)
    @day_pass_type = DayPassType.find(params[key])
  end

  def find_day_pass_types
    @day_pass_types = DayPassType.all
  end

  def day_pass_type_params
    params.require(:day_pass_type).permit(:name, :amount_in_cents, :available, :visible)
  end
end
