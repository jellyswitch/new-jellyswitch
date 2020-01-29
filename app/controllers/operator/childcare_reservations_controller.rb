class Operator::ChildcareReservationsController < Operator::BaseController
  before_action :background_image

  def index
    find_childcare_reservations
    authorize @childcare_reservations
  end
  
  def new
  end

  def select_slot
    @date = parse_date(params)
    @slots = current_location.childcare_slots.visible.where(week_day: @date.wday).order(:week_day, :name)
    if @slots.count < 1
      flash[:error] = "No childcare available on #{short_date(@date)}"
      turbolinks_redirect(new_childcare_reservation_path, action: "replace")
    end
  end

  def create
    date = Date.parse(params[:date])
    childcare_slot = current_location.childcare_slots.find(params[:childcare_slot_id])
    child_profile = current_user.child_profiles.find(params[:child_profile_id])

    @childcare_reservation = ChildcareReservation.new(
      date: date,
      childcare_slot: childcare_slot,
      child_profile: child_profile
    )
    if @childcare_reservation.save
      turbolinks_redirect(childcare_reservation_path(@childcare_reservation), action: "replace")
    else
      flash[:error] = "Something went wrong."
      turbolinks_redirect(new_childcare_reservation_path, action: "replace")
    end
  end

  def show
    find_childcare_reservation
    authorize @childcare_reservation
  end

  def destroy
    find_childcare_reservation
    authorize @childcare_reservation

    if @childcare_reservation.update(cancelled: true)
      flash[:success] = "Reservation cancelled."
      turbolinks_redirect(childcare_index_path, action: "replace")
    else
      flash[:error] = "Something went wrong."
      turbolinks_redirect(childcare_reservation_path(@childcare_reservation), action: "replace")
    end
  end

  private

  def find_childcare_reservation(key=:id)
    @childcare_reservation = ChildcareReservation.find(params[key])
  end

  def parse_date(obj)
    Date.new(obj["date(1i)"].to_i, obj["date(2i)"].to_i, obj["date(3i)"].to_i)
  end

  def childcare_reservation_params
    p = params.require(:childcare_reservation).permit(:childcare_slot_id, :child_profile_id)
    
    p
  end
end