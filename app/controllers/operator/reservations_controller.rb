class Operator::ReservationsController < Operator::BaseController
  def show
    find_reservation
    authorize @reservation
    background_image
  end

  def new
    @reservation = Reservation.new(reservation_params)
    authorize @reservation
    background_image
  end

  def create
    authorize Reservation.new
    result = CreateRoomReservation.call(reservation_params: reservation_params, user: current_user)
    @reservation = result.reservation

    if result.success?
      flash[:notice] = "Reserved #{@reservation.room.name} for #{@reservation.pretty_datetime}"
      redirect_to reservation_path(@reservation)
    else
      render :new
    end
  end

  def destroy
    find_reservation
    authorize @reservation

    if @reservation.destroy
      flash[:notice] = "Reservation cancelled."
      redirect_to root_path
    else
      flash[:error] = "There was a problem cancelling your reservation."
      redirect_to reservation_path(@reservation)
    end
  end

  private

  def find_reservation(key=:id)
    @reservation = Reservation.find(params[key]).decorate
  end

  def reservation_params
    params.require(:reservation).permit(:room_id, :datetime_in, :hours)
  end
end