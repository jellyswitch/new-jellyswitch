class Api::V1::Admin::ReservationsController < Api::V1::Admin::BaseController
  def index
    reservations = Reservation.unscoped
                              .joins(:room)
                              .where(rooms: { operator_id: current_tenant.id })
                              .where(cancelled: false)

    reservations = apply_scope(reservations, params[:scope])
    reservations = reservations.order(:datetime_in).limit(30).offset(params[:offset].to_i)

    render json: reservations.includes(:room, :user).map { |r| reservation_json(r) }
  end

  def calendar
    start_date = Time.zone.parse(params[:start])
    end_date = Time.zone.parse(params[:end])

    reservations = Reservation.unscoped
                              .joins(:room)
                              .where(rooms: { operator_id: current_tenant.id })
                              .where(cancelled: false)
                              .where(datetime_in: start_date..end_date)
                              .includes(:room, :user)

    render json: reservations.map { |r|
      {
        id: r.id,
        room_id: r.room_id,
        room_name: r.room&.name,
        user_name: r.user&.name,
        start: r.datetime_in,
        end: r.datetime_out
      }
    }
  end

  def create
    user = current_tenant.users.find(params[:user_id])
    room = Room.find(params[:room_id])
    datetime_in = Time.zone.parse(params[:datetime_in])
    minutes = params[:minutes].to_i

    day_pass_charge_info = user.day_pass_reservation_charge_info(room.location, datetime_in.to_date, minutes)
    subscription_charge_info = user.subscription_reservation_charge_info(room.location, minutes)

    result = Billing::Reservations::CreateRoomReservation.call(
      reservation_params: {
        datetime_in: datetime_in,
        hours: minutes / 60.0,
        minutes: minutes,
        room: room
      },
      user: user,
      location: room.location,
      day_pass_charge_info: day_pass_charge_info,
      subscription_charge_info: subscription_charge_info
    )

    if result.success?
      render json: reservation_json(result.reservation), status: :created
    else
      render_error(result.error || 'Booking failed')
    end
  end

  def extend
    reservation = Reservation.unscoped
                             .joins(:room)
                             .where(rooms: { operator_id: current_tenant.id })
                             .find(params[:id])

    new_minutes = params[:minutes].present? ? params[:minutes].to_i : (params[:hours].to_f * 60).to_i

    if reservation.update(minutes: new_minutes)
      render json: reservation_json(reservation)
    else
      render_error(reservation.errors.full_messages.join(', '))
    end
  end

  def destroy
    reservation = Reservation.unscoped
                             .joins(:room)
                             .where(rooms: { operator_id: current_tenant.id })
                             .find(params[:id])

    reservation.update!(cancelled: true)

    render json: { success: true }
  end

  private

  def apply_scope(reservations, scope)
    case scope
    when 'today'
      reservations.where(datetime_in: Date.current.beginning_of_day..Date.current.end_of_day)
    when 'upcoming'
      reservations.where("reservations.datetime_in > ?", Time.current)
    when 'past'
      reservations.where("reservations.datetime_in < ?", Time.current).order(datetime_in: :desc)
    else
      reservations
    end
  end

  def reservation_json(r)
    {
      id: r.id,
      room_name: r.room&.name,
      user_name: r.user&.name,
      date: r.datetime_in.strftime("%B %e, %Y"),
      time: r.datetime_in.strftime("%l:%M %p").strip,
      duration: "#{r.minutes} min",
      minutes: r.minutes,
      paid: r.paid,
      cancelled: r.cancelled
    }
  end
end
