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

  def stripe_connect_setup
    find_operator
    if params[:error].present?
      flash[:error] = params[:error_description]
    else
      # TODO: put this into an interactor
      stripe_code = params[:code]
      response = HTTParty.post("https://connect.stripe.com/oauth/token", 
        query: {
          client_secret: ENV['STRIPE_SECRET_KEY'],
          code: stripe_code,
          grant_type: "authorization_code"
        })
      if response["error"].present?
        flash[:error] = response["error_description"]
      else
        stripe_user_id = response["stripe_user_id"]
        stripe_publishable_key = response["stripe_publishable_key"]
        refresh_token = response["refresh_token"]
        access_token = response["access_token"]

        result = @operator.update(
          stripe_user_id: stripe_user_id,
          stripe_publishable_key: stripe_publishable_key,
          stripe_refresh_token: refresh_token,
          stripe_access_token: access_token
        )

        if result
          flash[:success] = "Your account has been connected to Stripe."
        else
          flash[:error] = "There was a problem storing your Stripe credentials."
        end
      end
    end
    redirect_to operator_path(@operator, subdomain: @operator.subdomain)
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