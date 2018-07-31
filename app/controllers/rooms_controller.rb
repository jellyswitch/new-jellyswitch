class RoomsController < ApplicationController
  def index
    find_rooms
    authorize @rooms
  end

  def show
    find_room
    authorize @room
  end

  def new
    @room = Room.new
    authorize @room
  end

  def create
    @room = Room.new(room_params)
    authorize @room

    if @room.save
      flash[:notice] = "Room #{@room.name} created."
      redirect_to room_path(@room)
    else
      render :new
    end
  end

  def edit
    find_room
    authorize @room
  end

  def update
    find_room
    authorize @room

    @room.update_attributes(room_params)

    if @room.save
      flash[:notice] = "Room #{@room.name} has been updated."
      redirect_to room_path(@room)
    else
      render :edit
    end
  end

  private

  def find_rooms
    @rooms = Room
  end

  def find_room(key=:id)
    @room = Room.friendly.find(params[key])
  end

  def room_params
    params.require(:room).permit(:name, :description, :whiteboard, :capacity)
  end
end