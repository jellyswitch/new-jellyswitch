class DoorsController < ApplicationController
  def index
    find_doors
    authorize @doors
  end

  def show
    find_door
    authorize @door
  end

  def new
    @door = Door.new
    authorize @door
  end

  def create
    @door = Door.new(door_params)
    authorize @door

    if @door.save
      flash[:notice] = "Door created."
      redirect_to doors_path(@door)
    else
      render :new
    end
  end

  def edit
    find_door
    authorize @door
  end

  def update
    find_door
    authorize @door

    @door.update_attributes(door_params)
    if @door.save
      flash[:notice] = "Door updated."
      redirect_to doors_path(@door)
    else
      render :edit
    end
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
end
