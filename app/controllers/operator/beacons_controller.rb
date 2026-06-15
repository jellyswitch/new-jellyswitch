class Operator::BeaconsController < Operator::BaseController
  def index
    @beacons = current_location.beacons.available.order(:name)
    authorize @beacons, policy_class: ::BeaconPolicy
    background_image
  end

  def show
    find_beacon
    authorize @beacon
    background_image
  end

  def new
    @beacon = Beacon.new(location: current_location, operator: current_tenant)
    authorize @beacon
    background_image
  end

  def create
    @beacon = Beacon.new(beacon_params.merge(location: current_location, operator: current_tenant))
    authorize @beacon

    if @beacon.save
      flash[:notice] = "Beacon created."
      turbo_redirect(beacons_path)
    else
      background_image
      render :new, status: 422
    end
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    raise
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  def edit
    find_beacon
    authorize @beacon
    background_image
  end

  def update
    find_beacon
    authorize @beacon

    if @beacon.update(beacon_params)
      flash[:notice] = "Beacon updated."
      turbo_redirect(beacons_path)
    else
      background_image
      render :edit, status: 422
    end
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    raise
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  def destroy
    find_beacon
    authorize @beacon, :destroy?

    if @beacon.update(available: false)
      flash[:notice] = "#{@beacon.name} archived."
      turbo_redirect(beacons_path)
    else
      flash[:error] = "Could not archive beacon."
      turbo_redirect(beacon_path(@beacon))
    end
  end

  def archived
    @beacons = current_location.beacons.unavailable.order(:name)
    authorize @beacons, policy_class: ::BeaconPolicy
    background_image
  end

  def unarchive
    find_beacon(:beacon_id)
    authorize @beacon
    if @beacon.update(available: true)
      flash[:success] = "Beacon unarchived."
    else
      flash[:error] = "Could not unarchive beacon."
    end
    turbo_redirect(beacons_path)
  end

  private

  def find_beacon(key = :id)
    @beacon = current_location.beacons.find(params[key])
  end

  def beacon_params
    params.require(:beacon).permit(:name, :uuid, :major, :minor, :door_id, :installed_at, :notes)
  end
end
