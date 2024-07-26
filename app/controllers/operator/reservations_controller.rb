class Operator::ReservationsController < Operator::BaseController
  before_action :background_image
  before_action :set_reserved_user, only: [:choose_day, :choose_time_post, :choose_time, :choose_duration, :confirm, :create_reservation]

  include ActionView::Helpers::NumberHelper
  include ReservationHelper
  include CreditHelper

  def show
    find_reservation
    authorize @reservation
    background_image
  end

  def choose_member
    authorize :reservation
    @room = current_tenant.rooms.find(params[:room_id])
    @next_step_path = params[:day].present? && params[:hour].present? ? choose_duration_reservations_path : choose_day_reservations_path
  end

  def choose_day
    # requires room, user
    @room = current_tenant.rooms.find(params[:room_id])
  end

  def choose_time_post
    @room = current_tenant.rooms.find(params[:room_id])
    if params[:day].present?
      @day = Date.parse(params[:day])
    else
      @day = Date.new(params["day(1i)"].to_i, params["day(2i)"].to_i, params["day(3i)"].to_i)
    end
    turbo_redirect choose_time_reservations_path(room_id: @room.id, user_id: @user.id, day: @day)
  end

  def choose_time
    # requires room, user, day
    @room = current_tenant.rooms.find(params[:room_id])
    if params[:day].present?
      @day = Date.parse(params[:day])
    else
      @day = Date.new(params["day(1i)"].to_i, params["day(2i)"].to_i, params["day(3i)"].to_i)
    end
  end

  def choose_duration
    # require room, user, day, time
    @room = current_tenant.rooms.find(params[:room_id])
    @day = Date.parse(params[:day])
    @hour = Time.strptime(params[:hour], "%l:%M%P")
    @staff = staff

    parse_time
  end

  def confirm
    # requires room, user, day, time, duration
    @room = current_tenant.rooms.find(params[:room_id])
    @day = Date.parse(params[:day])
    @hour = Time.strptime(params[:hour], "%l:%M%P")
    @duration = params[:duration].to_i

    @staff = staff

    parse_time
    if @user.should_charge_for_reservation?(current_location, @day) || !@user.has_billing?
      include_stripe
    end
  end

  def update_billing_and_create_reservation
    @room = current_tenant.rooms.find(params[:room_id])
    @day = Date.parse(params[:day])
    @hour = Time.strptime(params[:hour], "%l:%M%P")
    @duration = params[:duration].to_i

    parse_time

    token = params[:stripeToken]

    result = Billing::Reservations::UpdateBillingAndCreateRoomReservation.call(reservation_params: {
                                                                                 datetime_in: @datetime_in,
                                                                                 hours: @duration,
                                                                                 minutes: @duration.to_i,
                                                                                 room: @room,
                                                                               }, user: current_user,
                                                                               token: token,
                                                                               out_of_band: false)
    @reservation = result.reservation

    if result.success?
      flash[:notice] = "Reserved #{@reservation.room.name} for #{@reservation.pretty_datetime}"
      if current_user.approved?
        turbo_redirect(reservation_path(@reservation), action: restore_if_possible)
      else
        turbo_redirect(wait_path, action: restore_if_possible)
      end
    else
      flash[:error] = result.message
      if current_user.approved?
        turbo_redirect(confirm_reservations_path(room_id: @room.id, day: @day, hour: pretty_time(@hour), duration: @duration), action: "replace")
      else
        turbo_redirect(wait_path, action: restore_if_possible)
      end
    end
  end

  def create_reservation
    @room = current_tenant.rooms.find(params[:room_id])
    @day = Date.parse(params[:day])
    @hour = Time.strptime(params[:hour], "%l:%M%P")
    @duration = params[:duration].to_i
    parse_time

    result = Billing::Reservations::CreateRoomReservation.call(reservation_params: {
                                                                 datetime_in: @datetime_in,
                                                                 hours: @duration,
                                                                 minutes: @duration.to_i,
                                                                 room: @room,
                                                               }, user: @user)

    @reservation = result.reservation

    if result.success?
      flash[:notice] = "Reserved #{@reservation.room.name} for #{@reservation.pretty_datetime}"
      turbo_redirect(reservation_path(@reservation), action: restore_if_possible)
    else
      flash[:error] = result.message
      turbo_redirect(confirm_reservations_path(room_id: @room.id, day: @day, hour: pretty_time(@hour), duration: @duration), action: "replace")
    end
  end

  def destroy
    find_reservation
    authorize @reservation

    result = CancelReservation.call(reservation: @reservation)

    if result.success?
      flash[:notice] = "Reservation cancelled."
      turbo_redirect(root_path)
    else
      flash[:error] = result.message
      turbo_redirect(referrer_or_root)
    end
  rescue Exception => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  def today
    authorize Reservation
    @rooms = find_todays_reservations(current_tenant)
  end

  # New 'Reservation Now' flow

  def calendar
    @current_date = Time.zone.today
    if params[:reserve_now]
      @nearest_time_slot = calculate_nearest_time_slot(@current_date)
      @day_or_night = @nearest_time_slot.hour < 12 ? "day" : "night" if @nearest_time_slot
      @is_reserve_now = true
    end
    background_image
  end

  def available_time_slots
    if params[:day].present? && params[:day_or_night].present?
      @day = Date.parse(params[:day])
      @day_or_night = params[:day_or_night]
      @available_time_slots = calculate_available_time_slots(@day, @day_or_night)

      render json: @available_time_slots.map { |slot| slot.strftime("%I:%M") }
    else
      render json: { error: "Invalid date or day/night selection" }, status: :unprocessable_entity
    end
  end

  def available_rooms
    if params[:date].present? && params[:time].present? && params[:duration].present?
      date = params[:date]

      day_or_night = params[:day_or_night]
      time = params[:time]
      time += " pm" if day_or_night == "night"

      duration = params[:duration]

      available_rooms = current_location.rooms.available(date: date, time: time, duration: duration)

      if !current_user.can_see_all_rooms?(current_location)
        available_rooms = available_rooms.rentable
      end

      render json: available_rooms, only: [:id, :name, :photo, :capacity, :hourly_rate_in_cents]
    else
      render json: { error: "Invalid or missing parameters" }, status: :unprocessable_entity
    end
  end

  def room_price_and_details
    if params[:room_id].present? && params[:duration].present? && params[:date].present?
      room = Room.find(params[:room_id])
      duration = params[:duration].to_i
      date = Time.zone.parse(params[:date])

      should_charge = current_user.should_charge_for_reservation?(current_location, date)

      hourly_price = room.hourly_rate_in_cents / 100.0
      reservation_price = room.hourly_rate_in_cents / 100.0 * (duration / 60.0)

      render json: {
        id: room.id,
        name: room.name,
        hourly_price: hourly_price,
        capacity: room.capacity,
        reservation_price: reservation_price,
        should_charge: should_charge,
        amenities: room.amenities,
      }
    else
      render json: { error: "Invalid or missing parameters" }, status: :unprocessable_entity
    end
  end

  def create
    reservation_params = create_reservation_params

    @room = current_tenant.rooms.find(reservation_params[:room_id])
    @day = Date.parse(reservation_params[:date])

    @day_or_night = reservation_params[:day_or_night]
    @hour = Time.strptime(reservation_params[:time], "%I:%M")

    amenity_ids = params[:amenity_ids] || []

    # Adjust for AM/PM
    if @day_or_night == "night" && @hour.hour != 12
      @hour += 12.hours
    elsif @day_or_night == "day" && @hour.hour == 12
      @hour -= 12.hours
    end

    @duration = reservation_params[:duration].to_i
    parse_time

    result = Billing::Reservations::CreateRoomReservation.call(reservation_params: {
                                                                 datetime_in: @datetime_in,
                                                                 hours: @duration / 60,
                                                                 minutes: @duration.to_i,
                                                                 room: @room,
                                                                 amenity_ids: amenity_ids,
                                                                 note: reservation_params[:note],
                                                               }, user: current_user)

    @reservation = result.reservation

    if result.success?
      flash[:notice] = "Reserved #{@reservation.room.name} for #{@reservation.pretty_datetime}"
      turbo_redirect(reservation_path(@reservation), action: restore_if_possible)
    else
      flash[:error] = result.message
      turbo_redirect(calendar_reservations_path, action: "replace")
    end
  end

  def available_extension_durations
    reservation = Reservation.find(params[:id])
    room = reservation.room

    available_durations = room.calculate_available_durations(start_time: reservation.datetime_out)

    render json: available_durations
  end

  def calculate_additional_hour_price
    reservation = Reservation.find(params[:id])
    room = reservation.room

    additional_duration = params[:duration].to_i
    additional_price = number_to_currency((room.hourly_rate_in_cents / 100.0) * (additional_duration / 60.0))

    reservation.assign_attributes({ minutes: reservation.minutes + additional_duration })

    render json: {
      additional_price: additional_price,
      new_end_time: reservation.datetime_out.strftime("%m/%d/%Y at %l:%M%P"),
      should_charge: reservation.paid?,
    }
  end

  def extend_reservation
    reservation = Reservation.find(params[:id])

    additional_duration = params[:duration].to_i

    result = Billing::Reservations::ExtendReservation.call(reservation: reservation, additional_duration: additional_duration, user: reservation.user)

    if result.success?
      flash[:notice] = "Reservation extended successfully."
      turbo_redirect(reservation_path(reservation), action: restore_if_possible)
    else
      flash[:error] = result.message
      turbo_redirect(reservation_path(reservation), action: "replace")
    end
  end

  def end_now
    find_reservation
    authorize @reservation, :end_now?

    if @reservation.end_now!
      flash[:notice] = "Reservation ended early successfully."
      turbo_redirect(reservation_path(@reservation), action: restore_if_possible)
    else
      flash[:error] = "An error occurred while ending the reservation early."
      turbo_redirect(reservation_path(@reservation), action: "replace")
    end
  end

  def update_note
    find_reservation

    if @reservation.update(note: params[:reservation][:note])
      flash[:notice] = "Reservation note updated successfully."
      turbo_redirect(reservation_path(@reservation), action: restore_if_possible)
    else
      flash[:error] = "An error occurred while update the reservation note."
      turbo_redirect(reservation_path(@reservation), action: "replace")
    end
  end

  private

  def find_reservation(key = :id)
    @reservation = Reservation.find(params[key]).decorate
  end

  def set_reserved_user
    if staff
      @user = User.for_space(current_tenant).find_by(id: params[:user_id]) || current_user
    else
      @user = current_user
    end
  end

  def staff
    current_user.admin? || current_user.general_manager? || current_user.community_manager?
  end

  def create_reservation_params
    params.permit(:room_id, :date, :time, :duration, :day_or_night, :note)
  end

  def reservation_params
    params.require(:reservation).permit(:room_id, :datetime_in, :hours)
  end

  def flatten_date_array(hash)
    %w(1 2 3).map { |e| hash["date(#{e}i)"].to_i }
  end

  def parse_time
    zone = ActiveSupport::TimeZone[@room.location.time_zone]
    offset = zone.now.formatted_offset
    time_input = "#{short_date(@day)} #{pretty_time(@hour)} #{offset}"
    @datetime_in = Time.strptime(time_input, "%m/%d/%Y %l:%M%P %Z")
  end
end
