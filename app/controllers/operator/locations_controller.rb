class Operator::LocationsController < Operator::BaseController
  before_action :find_location, only: [:show, :edit, :update, :destroy]
  before_action :background_image

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
      flash[:success] = "Location created."
      turbolinks_redirect location_path(@location)
    else
      flash[:error] = "Could not save location."
      render :new
    end
  end

  def show
    authorize @location
  end

  def edit
    authorize @location
  end

  def update
    authorize @location

    if @location.update(location_params)
      flash[:success] = "Location updated."
      turbolinks_redirect location_path(@location)
    else
      flash[:error] = "Could not update location."
      render :new
    end
  end

  def destroy
    authorize @location

    if @location.destroy
      flash[:success] = "Location removed."
      turbolinks_redirect location_path(@location)
    else
      flash[:error] = "Could not remove location."
      render :new
    end
  end

  private

  def find_location
    @location = Location.find(params[:id])
  end

  def location_params
    params.require(:location).permit(
      :name, :snippet, :wifi_name, :wifi_password, :building_address,
      :city, :state, :zip, :contact_name, :contact_email, :contact_phone,
      :background_image, :square_footage, :time_zone, :visible,
      :flex_square_footage, :common_square_footage, :building_access_instructions,
      :allow_hourly, :hourly_rate_in_cents, :new_users_get_free_day_pass,
      :open_sunday, :open_monday, :open_tuesday, :open_wednesday, :open_thursday,
      :open_friday, :open_saturday
    )
  end
end
