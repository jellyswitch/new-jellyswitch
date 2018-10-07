class DoorsController < ApplicationController
  def index
    find_doors
    authorize @doors
    background_image
  end

  def show
    find_door
    authorize @door
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
      redirect_to doors_path(@door)
    else
      background_image
      render :new
    end
  end

  def edit
    find_door
    authorize @door
    background_image
  end

  def update
    find_door
    authorize @door

    @door.update_attributes(door_params)
    if @door.save
      flash[:notice] = "Door updated."
      redirect_to doors_path(@door)
    else
      background_image
      render :edit
    end
  end

  def keys
    find_doors
    authorize @doors
    background_image
  end

  def open
    find_door(:door_id)
    authorize @door
    log_door_punch
    OpenDoorJob.perform_later(@door)
    redirect_to keys_doors_path
  end

  private

  def find_doors
    @doors = Door.all
  end

  def find_door(key=:id)
    @door = Door.friendly.find(params[key])
  end

  def door_params
    params.require(:door).permit(:name)
  end

  def log_door_punch
    DoorPunch.create!(user: current_user, door: @door)
  end
end
