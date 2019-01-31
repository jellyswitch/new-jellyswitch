class OperatorsController < ApplicationController
  def index
    find_operators
    authorize @operators
  end

  def show
    find_operator
    authorize @operator
  end

  def new
    @operator = Operator.new
    authorize @operator
  end

  def edit
    find_operator
    authorize @operator
  end

  def create
    @operator = Operator.new(operator_params)
    authorize @operator

    if @operator.save
      flash[:success] = "Operator created."
      redirect_to operator_path(@operator)
    else
      render :new
    end
  end

  def update
    find_operator
    authorize @operator

    @operator.update_attributes(operator_params)

    if @operator.save
      flash[:success] = "Operator has been updated."
      redirect_to operator_path(@operator)
    else
      render :edit, status: 422
    end
  end

  private

  def find_operators
    @operators = Operator.all
  end

  def find_operator(key=:id)
    @operator = Operator.find(params[key])
  end

  def operator_params
    params.require(:operator).permit(:name, :snippet, :background, :wifi_name, :wifi_password, :building_address, 
      :logo, :approval_required, :subdomain, :contact_name, :contact_email, :contact_phone)
  end
end