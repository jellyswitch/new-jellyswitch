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
    date = datetime_in.to_date

    # If a stripe_token is provided, save the card to the user first
    # so it's stored for future one-tap bookings.
    stripe_token = params[:stripe_token] || params.dig(:reservation, :stripe_token)
    if stripe_token.present?
      begin
        Billing::Payment::UpdateUserPayment.call(
          user: current_api_user,
          location: current_location,
          token: stripe_token,
          out_of_band: false,
        )
      rescue => e
        Rails.logger.error("Failed to save payment method: #{e.message}")
      end
    end

    day_pass_charge_info = current_api_user.day_pass_reservation_charge_info(current_location, date, minutes, room: room)
    subscription_charge_info = current_api_user.subscription_reservation_charge_info(current_location, minutes, room: room)

    result = Billing::Reservations::CreateRoomReservation.call(
      reservation_params: {
        datetime_in: datetime_in,
        hours: minutes / 60.0,
        minutes: minutes,
        room: room,
      },
      user: current_api_user,
      location: current_location,
      day_pass_charge_info: day_pass_charge_info,
      subscription_charge_info: subscription_charge_info,
    )

    if result.success?
      render json: reservation_json(result.reservation), status: :created
    else
      render_error(result.error || 'Booking failed')
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
