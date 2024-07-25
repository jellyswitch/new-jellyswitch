class Operator::RoomsController < Operator::BaseController
  include RoomsHelper
  include SessionsHelper
  decorates_assigned :rooms, :hidden_rooms, :room, :rentable_rooms, :reservations

  def index
    find_rooms
    authorize @rooms
    background_image
  end

  def show
    find_room
    if request.format != :ics
      authorize @room
    end
    background_image

    @pagy, @reservations = pagy(Reservation.for_room(@room).order(datetime_in: :desc))

    respond_to do |format|
      format.html
      format.ics do
        response.set_header("Content-Type", "text/calendar")
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
      flash[:success] = "Room added."
      if params[:add_room_and_add_another].present?
        turbo_redirect(new_room_path, action: "replace")
      else
        turbo_redirect(room_path(@room))
      end
    else
      render :new, status: 422
    end
  rescue Exception => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  def edit
    find_room
    authorize @room
    background_image
    @room.amenities.build if @room.amenities.empty?
  end

  def destroy
    find_room
    authorize @room, :destroy?

    if @room.destroy
      flash[:notice] = "#{@room.name} deleted."
      redirect_to rooms_path
    else
      flash[:error] = "Could not delete room."
      redirect_to room_path(@room)
    end
  end

  def update
    find_room
    authorize @room

    @room.update(room_params)
    handle_amenity_deletions_if_needed

    if @room.save
      flash[:notice] = "Room #{@room.name} has been updated."
      turbo_redirect(room_path(@room))
    else
      flash[:error] = @room.errors.full_messages.to_sentence
      turbo_redirect(referrer_or_root)
    end
  rescue Exception => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  private

  def find_rooms
    @rooms = current_location.rooms.visible.order(:name).all
    @hidden_rooms = current_location.rooms.invisible.order(:name).all
    @rentable_rooms = current_location.rooms.rentable.cheapest.all
  end

  def find_room(key = :id)
    @room = if logged_in?
      Room
    else
      Room.unscoped
    end.friendly.find(params[key])
  end

  def handle_amenity_deletions_if_needed
    return unless params[:room][:amenities_attributes]

    params[:room][:amenities_attributes].each do |_, amenity_attrs|
      if amenity_attrs[:_destroy] == "1" && amenity_attrs[:id].present?
        Amenity.find(amenity_attrs[:id]).destroy
      end
    end
  end
end
