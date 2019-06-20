class Operator::RoomsController < Operator::BaseController
  def index
    find_rooms
    authorize @rooms
    @rooms = @rooms.decorate
    @hidden_rooms = Room.invisible.order(:name).all.decorate
    background_image
  end

  def show
    find_room
    if request.format != :ics
      authorize @room
    end
    background_image

    @pagy, @reservations = pagy(Reservation.for_room(@room))

    @reservations = @reservations.decorate
    respond_to do |format|
      format.html
      format.ics do
        render plain: @room.calendar.to_ical
      end
    end
  end

  def new
    @room = Room.new
    authorize @room
    background_image
  end

  def create
    @room = Room.new(room_params)
    authorize @room

    if @room.save
      flash[:notice] = "Room #{@room.name} created."
      turbolinks_redirect(room_path(@room))
    else
      render :new, status: 422
    end
  rescue Exception => e
    Rollbar.error(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbolinks_redirect(referrer_or_root)
  end

  def edit
    find_room
    authorize @room
    background_image
  end

  def update
    find_room
    authorize @room

    @room.update_attributes(room_params)

    if @room.save
      flash[:notice] = "Room #{@room.name} has been updated."
      turbolinks_redirect(room_path(@room))
    else
      render :edit, status: 422
    end
  rescue Exception => e
    Rollbar.error(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbolinks_redirect(referrer_or_root)
  end

  private

  def find_rooms
    @rooms = Room.visible.order(:name).all
  end

  def find_room(key=:id)
    @room = Room.friendly.find(params[key]).decorate
  end

  def room_params
    params.require(:room).permit(
      :name, 
      :description, 
      :whiteboard, 
      :capacity, 
      :square_footage, 
      :photo, 
      :visible, 
      :av,
      :rentable,
      :hourly_rate_in_cents
      )
  end
end
