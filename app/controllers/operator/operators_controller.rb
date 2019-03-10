class Operator::OperatorsController < Operator::BaseController
  before_action :background_image

  def show
    find_operator
    authorize @operator
  end

  def edit
    find_operator
    authorize @operator
  end

  def update
    find_operator

    @operator.update_attributes(operator_params)

    if @operator.save
      flash[:success] = "Operator has been updated."
      redirect_to operator_path(@operator)
    else
      render :edit, status: 422
    end
  end

  private

  def find_operator
    @operator = current_tenant
  end

  def operator_params
    params.require(:operator).permit(:name, :snippet, :wifi_name, :wifi_password, :building_address, 
      :approval_required, :contact_name, :contact_email, :contact_phone,
      :background_image, :logo_image, :square_footage, :kisi_api_key, :terms_of_service)
  end
end