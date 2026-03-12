class Operator::DoorsController < Operator::BaseController
  def index
    find_doors
    authorize @doors, policy_class: ::DoorPolicy
    background_image
  end

  def show
    find_door
    authorize @door
    @pagy, @punches = pagy(@door.door_punches.order("created_at DESC"))
    background_image
  end

  def new
    @door = Door.new
    authorize @door
    background_image
  end

  def create
    @door = Door.new(door_params)
    authorize @door

    if @door.save
      flash[:notice] = "Door created."
      turbo_redirect(door_path(@door))
    else
      background_image
      render :new, status: 422
    end
  rescue Exception => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  def edit
    find_door
    authorize @door
    background_image
  end

  def destroy
    find_door
    authorize @door, :destroy?

    if @door.destroy
      flash[:notice] = "#{@door.name} deleted."
      redirect_to doors_path
    else
      flash[:error] = "Could not delete door."
      redirect_to door_path(@door)
    end
  end

  def update
    find_door
    authorize @door

    @door.update(door_params)
    if @door.save
      flash[:notice] = "Door updated."
      turbo_redirect(doors_path(@door))
    else
      background_image
      render :edit, status: 422
    end
  rescue Exception => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  def keys
    find_doors
    authorize @doors, policy_class: ::DoorPolicy
    background_image
  end

  def open
    find_door(:door_id)
    authorize @door
    log_door_punch

    # Call Kisi API inline instead of via background job for reliability
    begin
      kisi_url = "https://api.kisi.io/locks/#{@door.kisi_id}/unlock"
      kisi_headers = {
        'Accept' => 'application/json',
        'Content-type' => 'application/json',
        'Authorization' => "KISI-LOGIN #{@door.location.kisi_api_key}"
      }
      kisi_result = HTTParty.post(kisi_url, headers: kisi_headers)
      DoorPunch.create(user: current_user, door: @door, operator: current_tenant, json: kisi_result.parsed_response)
      Rails.logger.info("[DoorOpen] #{@door.name} kisi_id=#{@door.kisi_id} => #{kisi_result.code}")

      if !kisi_result.success?
        Rails.logger.error("[DoorOpen] Kisi error: #{kisi_result.code} #{kisi_result.body}")
      end
    rescue => e
      Rails.logger.error("[DoorOpen] Error unlocking #{@door.name}: #{e.class}: #{e.message}")
      Honeybadger.notify(e)
    end

    respond_to do |format|
      format.html {
        if !untethered_ios_request?
          response.headers["Turbo-Location"] = home_url
          redirect_to home_path
        else
          response.headers["Turbo-Location"] = home_url
          redirect_to home_path
        end
      }
      format.js {
        # render open.js.erb template
      }
    end
  end

  private

  def find_doors
    @doors = current_location.doors
    @doors = @doors.where(private: [false, nil]) unless admin?
  end

  def find_door(key = :id)
    @door = Door.friendly.find(params[key])
  end

  def door_params
    params.require(:door).permit(:name, :kisi_id, :private)
  end

  def log_door_punch
    DoorPunch.create!(user: current_user, door: @door, operator: current_tenant)
  end
end
