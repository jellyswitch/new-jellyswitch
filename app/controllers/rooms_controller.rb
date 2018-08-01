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

  def day
    find_room(:room_id)
    authorize @room

    @day = params[:day].to_i
    @month = params[:month].to_i
    @year = params[:year].to_i

    @day_start = DateTime.new(@year, @month, @day).beginning_of_hour
    @previous_day = @day_start - 1.day
    @next_day = @day_start + 1.day
    
    @hours = @room.availability_for_day(@day_start)
  end

  def reserve
    
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