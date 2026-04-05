class Api::V1::ReservationsController < Api::V1::BaseController
  def index
    user = current_api_user
    upcoming = user.reservations.where(cancelled: false).where("datetime_in > ?", Time.current).order(:datetime_in).limit(20)
    past = user.reservations.where(cancelled: false).where("datetime_in <= ?", Time.current).order(datetime_in: :desc).limit(10)

    render json: {
      upcoming: upcoming.map { |r| reservation_json(r) },
      past: past.map { |r| reservation_json(r) },
    }
  end

  def create
    room = Room.find(params[:reservation][:room_id])
    datetime_in = Time.parse(params[:reservation][:datetime_in])
    minutes = params[:reservation][:minutes].to_i

    reservation = Reservation.new(
      room: room,
      user: current_api_user,
      datetime_in: datetime_in,
      minutes: minutes,
      hours: minutes / 60.0,
    )

    if reservation.save
      # Schedule reminders
      render json: reservation_json(reservation), status: :created
    else
      render_error(reservation.errors.full_messages.first)
    end
  end

  def destroy
    reservation = current_api_user.reservations.find(params[:id])
    reservation.update(cancelled: true)
    render json: { success: true }
  rescue ActiveRecord::RecordNotFound
    render_error('Reservation not found', status: :not_found)
  end

  private

  def reservation_json(r)
    {
      id: r.id,
      room_name: r.room.name,
      date: r.datetime_in.strftime("%B %e, %Y"),
      time: r.datetime_in.strftime("%l:%M %p").strip,
      duration: "#{r.minutes} min",
      minutes: r.minutes,
      paid: r.paid,
      cancelled: r.cancelled,
    }
  end
end
