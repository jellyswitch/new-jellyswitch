class Operator::LocationsController < Operator::BaseController
  def index
    @locations = Location.all
    authorize @locations
  end

  def new
    @location = Location.new
    authorize @location
  end

  def create
    @location = Location.new(location_params)

    authorize @location

    if @location.save
      flash[:success] = "location created."
      turbolinks_redirect location_path(@location)
    else
      render :new
    end
  end

  def show
  end

  def edit
  end

  def update
  end

  def destroy
  end

  private

  def location_params
    params.require(:location).permit(
      :name, :snippet, :wifi_name, :wifi_password, :building_address,
      :city, :state, :zip, :contact_name, :contact_email, :contact_phone,
      :background_image, :square_footage
    )
  end
end
