class ReservationsController < ApplicationController
  def show
    find_reservation
    authorize @reservation
  end

  def new
    @reservation = Reservation.new
    authorize @reservation
  end

  def create
    @reservation = Reservation.new(reservation_params)
    authorize @reservation

    @reservation.user = current_user
    # TODO: Make sure the room isn't already booked here

    if @reservation.save
      flash[:notice] = "Reserved #{@reservation.room.name} for #{@reservation.pretty_datetime}"
      redirect_to reservation_path(@reservation)
    else
      render :new
    end
  end

  private

  def find_reservation(key=:id)
    @reservation = Reservation.find(params[key])
  end

  def reservation_params
    params.require(:reservation).permit(:room_id, :datetime_in, :hours)
  end
end