class Operator::ReservationsController < Operator::BaseController
  before_action :background_image
  before_action :set_reserved_user, only: [:choose_day, :choose_time_post, :choose_time, :choose_duration, :confirm, :create_reservation]

  include ActionView::Helpers::NumberHelper
  include ReservationHelper
  include CreditHelper

  def show
    find_reservation
    authorize @reservation
    @reservation = @reservation.decorate
    background_image
  end

  def choose_member
    authorize :reservation
    @room = current_tenant.rooms.find(params[:room_id])
    @next_step_path = params[:day].present? && params[:hour].present? ? choose_duration_reservations_path : choose_day_reservations_path
    all_options = User.lease_options_for_select(current_tenant, current_location)

    # Filter to eligible members only
    eligible = Set.new([current_user.id])

    # Admins/managers
    begin
      eligible.merge(User.for_space(current_tenant).where(role: [User::ADMIN, User::GENERAL_MANAGER, User::COMMUNITY_MANAGER]).pluck(:id))
    rescue => e
      Rails.logger.error("choose_member admins error: #{e.class}: #{e.message}")
    end

    # Active subscribers (subscribable is polymorphic — subscribable_type "User" means subscribable_id is the user_id)
    begin
      plan_ids = Plan.where(location_id: current_location.id).pluck(:id)
      if plan_ids.any?
        eligible.merge(Subscription.where(active: true, plan_id: plan_ids, subscribable_type: "User").pluck(:subscribable_id))
      end
    rescue => e
      Rails.logger.error("choose_member subscribers error: #{e.class}: #{e.message}")
    end

    # Organization subscribers — orgs with active subscriptions, then their member user IDs
    begin
      if plan_ids.present? && plan_ids.any?
        org_ids = Subscription.where(active: true, plan_id: plan_ids, subscribable_type: "Organization").pluck(:subscribable_id)
        eligible.merge(User.for_space(current_tenant).where(organization_id: org_ids).pluck(:id)) if org_ids.any?
      end
    rescue => e
      Rails.logger.error("choose_member org_subscribers error: #{e.class}: #{e.message}")
    end

    # Organization members with active office leases at this location
    begin
      lease_org_ids = OfficeLease.active.where(location_id: current_location.id).pluck(:organization_id)
      eligible.merge(User.for_space(current_tenant).where(organization_id: lease_org_ids).pluck(:id)) if lease_org_ids.any?
    rescue => e
      Rails.logger.error("choose_member lease_members error: #{e.class}: #{e.message}")
    end

    # Day pass holders (today or future)
    begin
      eligible.merge(DayPass.where("day >= ?", Time.current.to_date).pluck(:user_id))
    rescue => e
      Rails.logger.error("choose_member day_passes error: #{e.class}: #{e.message}")
    end

    # Users with current or future reservations
    begin
      eligible.merge(Reservation.where("datetime_in >= ?", Time.current).pluck(:user_id))
    rescue => e
      Rails.logger.error("choose_member reservations error: #{e.class}: #{e.message}")
    end

    all_options = all_options.select { |_name, id| eligible.include?(id) } if eligible.size > 1

    admin_option = all_options.find { |_name, id| id == current_user.id }
    admin_option ||= [current_user.name, current_user.id]
    others = all_options.reject { |_name, id| id == current_user.id }
    @member_options = [admin_option] + others
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
    should_charge = @user.should_charge_for_reservation?(current_location, @day)

    # Check subscription overage
    if !should_charge && @duration.present?
      begin
        sub_info = @user.subscription_reservation_charge_info(current_location, @duration)
        should_charge = true if sub_info && sub_info[:charge_type] == :partial_overage
      rescue => e
        Rails.logger.error("subscription_reservation_charge_info error in confirm: #{e.class}: #{e.message}")
        Honeybadger.notify(e)
      end
    end

    if should_charge || !@user.has_billing_for_location?(current_location)
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
                                                                               location: current_location,
                                                                               token: token,
                                                                               out_of_band: false)
    @reservation = result.reservation

    if result.success?
      flash[:notice] = "Reserved #{@reservation.room.name} for #{@reservation.pretty_datetime}"
      session[:should_track_pixels] = true
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

    # Compute subscription overage info for members
    begin
      subscription_charge_info = @user.subscription_reservation_charge_info(current_location, @duration)
    rescue => e
      Rails.logger.error("subscription_reservation_charge_info error in create_reservation: #{e.class}: #{e.message}")
      Honeybadger.notify(e)
      subscription_charge_info = nil
    end

    result = Billing::Reservations::CreateRoomReservation.call(reservation_params: {
                                                                 datetime_in: @datetime_in,
                                                                 hours: @duration,
                                                                 minutes: @duration.to_i,
                                                                 room: @room,
                                                               }, user: @user, location: current_location,
                                                               subscription_charge_info: subscription_charge_info)

    @reservation = result.reservation

    if result.success?
      flash[:notice] = "Reserved #{@reservation.room.name} for #{@reservation.pretty_datetime}"
      redirect_to reservation_path(@reservation)
    else
      flash[:error] = result.message
      redirect_to confirm_reservations_path(room_id: @room.id, day: @day, hour: pretty_time(@hour), duration: @duration)
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
    @rooms = find_todays_reservations(current_location)
  end

  # New 'Reservation Now' flow

  def calendar
    include_stripe
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

      if @day_or_night == "all"
        @available_time_slots = calculate_all_available_time_slots(@day)
        render json: @available_time_slots.map { |slot| slot.strftime("%I:%M %p") }
      else
        @available_time_slots = calculate_available_time_slots(@day, @day_or_night)
        render json: @available_time_slots.map { |slot| slot.strftime("%I:%M") }
      end
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

      parsed_date = Time.zone.parse(date)
      if !current_user.can_see_all_rooms?(current_location, parsed_date)
        available_rooms = available_rooms.rentable
      end

      render json: available_rooms, only: [:id, :name, :photo, :capacity, :hourly_rate_in_cents]
    else
      render json: { error: "Invalid or missing parameters" }, status: :unprocessable_entity
    end
  end

  def max_available_duration
    if params[:date].present? && params[:time].present? && params[:day_or_night].present?
      date = params[:date]
      day_or_night = params[:day_or_night]
      time = params[:time]
      time += " pm" if day_or_night == "night"

      parsed_date = Date.parse(date)
      parsed_time = Time.zone.parse("#{date} #{time}")

      rooms = current_location.rooms.visible
      rooms = rooms.rentable unless current_user.can_see_all_rooms?(current_location, parsed_date)

      max_duration = 0
      rooms.each do |room|
        durations = room.calculate_max_continuous_duration(start_time: parsed_time)
        max_duration = [max_duration, durations].max
      end

      render json: { max_duration: [max_duration, 480].min }
    else
      render json: { error: "Invalid parameters" }, status: :unprocessable_entity
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

      # Check day pass overage for day pass holders
      begin
        day_pass_charge_info = current_user.day_pass_reservation_charge_info(current_location, date.to_date, duration)
      rescue => e
        Rails.logger.error("day_pass_reservation_charge_info error: #{e.class}: #{e.message}")
        Honeybadger.notify(e)
        day_pass_charge_info = nil
      end

      response = {
        id: room.id,
        name: room.name,
        hourly_price: hourly_price,
        capacity: room.capacity,
        reservation_price: reservation_price,
        should_charge: should_charge,
        is_day_pass_overage: false,
        amenities: room.amenities,
      }

      if day_pass_charge_info
        if day_pass_charge_info[:charge_type] == :partial_overage
          response[:should_charge] = true
          response[:is_day_pass_overage] = true
          response[:reservation_price] = day_pass_charge_info[:overage_amount_in_cents] / 100.0
          response[:included_minutes_remaining] = day_pass_charge_info[:remaining_free]
          response[:overage_minutes] = day_pass_charge_info[:overage_minutes_rounded]
          response[:overage_rate_hourly] = day_pass_charge_info[:overage_rate_in_cents] / 100.0
        else
          response[:should_charge] = false
          response[:reservation_price] = 0
          response[:included_minutes_remaining] = day_pass_charge_info[:remaining_free]
        end
      end

      # Check subscription meeting room overage for members
      begin
        subscription_charge_info = current_user.subscription_reservation_charge_info(current_location, duration)
      rescue => e
        Rails.logger.error("subscription_reservation_charge_info error: #{e.class}: #{e.message}")
        Honeybadger.notify(e)
        subscription_charge_info = nil
      end

      if subscription_charge_info
        if subscription_charge_info[:charge_type] == :partial_overage
          response[:should_charge] = true
          response[:is_subscription_overage] = true
          response[:reservation_price] = subscription_charge_info[:overage_amount_in_cents] / 100.0
          response[:included_minutes_remaining] = subscription_charge_info[:remaining_free]
          response[:overage_minutes] = subscription_charge_info[:overage_minutes_rounded]
          response[:overage_rate_hourly] = subscription_charge_info[:overage_rate_in_cents] / 100.0
          response[:used_minutes] = subscription_charge_info[:used_minutes]
          response[:included_minutes] = subscription_charge_info[:included_minutes]
        elsif !day_pass_charge_info
          response[:should_charge] = false
          response[:reservation_price] = 0
          response[:included_minutes_remaining] = subscription_charge_info[:remaining_free]
          response[:used_minutes] = subscription_charge_info[:used_minutes]
          response[:included_minutes] = subscription_charge_info[:included_minutes]
        end
      end

      render json: response
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

    token = params[:stripeToken]

    # Compute day pass overage info for the interactor chain
    begin
      day_pass_charge_info = current_user.day_pass_reservation_charge_info(current_location, @day, @duration)
    rescue => e
      Rails.logger.error("day_pass_reservation_charge_info error in create: #{e.class}: #{e.message}")
      Honeybadger.notify(e)
      day_pass_charge_info = nil
    end

    # Compute subscription overage info
    begin
      subscription_charge_info = current_user.subscription_reservation_charge_info(current_location, @duration)
    rescue => e
      Rails.logger.error("subscription_reservation_charge_info error in create: #{e.class}: #{e.message}")
      Honeybadger.notify(e)
      subscription_charge_info = nil
    end

    # Validate discount code if provided
    discount_code = nil
    if params[:discount_code].present?
      validate_result = Billing::DiscountCodes::ValidateCode.call(
        code: params[:discount_code],
        location: current_location,
        product_type: "meeting_room"
      )
      if validate_result.success?
        discount_code = validate_result.discount_code
      else
        flash[:error] = validate_result.message
        turbo_redirect(calendar_reservations_path, action: "replace")
        return
      end
    end

    interactor = if token.present?
      Billing::Reservations::UpdateBillingAndCreateRoomReservation
    else
      Billing::Reservations::CreateRoomReservation
    end

    result = interactor.call(reservation_params: {
                               datetime_in: @datetime_in,
                               hours: @duration / 60,
                               minutes: @duration.to_i,
                               room: @room,
                               amenity_ids: amenity_ids,
                               note: reservation_params[:note],
                             }, user: current_user, location: current_location,
                             token: token, out_of_band: false,
                             day_pass_charge_info: day_pass_charge_info,
                             subscription_charge_info: subscription_charge_info,
                             discount_code: discount_code)

    @reservation = result.reservation

    if result.success?
      flash[:notice] = "Reserved #{@reservation.room.name} for #{@reservation.pretty_datetime}"
      session[:should_track_pixels] = true
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

  def needs_billing
    date = Time.zone.parse(params[:date])
    should_charge = current_user.should_charge_for_reservation?(current_location, date)

    # Check day pass overage: if user is day pass holder and booking exceeds included time
    if !should_charge && params[:duration].present? && current_user.has_active_day_pass?(date.to_date)
      duration = params[:duration].to_i
      charge_info = current_user.day_pass_reservation_charge_info(current_location, date.to_date, duration)
      if charge_info && charge_info[:charge_type] == :partial_overage
        should_charge = true
      end
    end

    # Check subscription overage: if member's plan has meeting room limits
    if !should_charge && params[:duration].present?
      begin
        duration = params[:duration].to_i
        sub_info = current_user.subscription_reservation_charge_info(current_location, duration)
        if sub_info && sub_info[:charge_type] == :partial_overage
          should_charge = true
        end
      rescue => e
        Rails.logger.error("subscription_reservation_charge_info error in needs_billing: #{e.class}: #{e.message}")
        Honeybadger.notify(e)
      end
    end

    has_billing = current_user.has_billing_for_location?(current_location)

    render json: { needs_billing: should_charge && !has_billing }
  end

  def daily_counts
    start_date = Date.parse(params[:start_date])
    end_date = Date.parse(params[:end_date])

    reservations = Reservation.for_location_id(current_location.id).not_cancelled
                            .where(datetime_in: start_date.beginning_of_day..end_date.end_of_day)

    if params[:room_id].present?
      reservations = reservations.where(room_id: params[:room_id])
    end

    pg_timezone = ActiveSupport::TimeZone::MAPPING[current_location.time_zone]

    counts = reservations.group(
      "DATE(datetime_in AT TIME ZONE 'UTC' AT TIME ZONE '#{pg_timezone}')"
    ).count

    formatted_counts = {}
    (start_date..end_date).each do |date|
      formatted_counts[date.strftime("%Y-%m-%d")] = counts[date] || 0
    end

    render json: formatted_counts
  end

  def daily_details
    date = Date.parse(params[:date])

    # Get reservations for the full day in location's timezone
    start_time = date.in_time_zone(current_location.time_zone).beginning_of_day
    end_time = date.in_time_zone(current_location.time_zone).end_of_day

    reservations = Reservation.for_location_id(current_location.id)
                            .not_cancelled
                            .includes(:room) # Eager load room to avoid N+1
                            .where(datetime_in: start_time..end_time)
                            .order(datetime_in: :asc)

    reservation_details = reservations.map do |reservation|
      {
        id: reservation.id,
        datetime_in: reservation.datetime_in.in_time_zone(current_location.time_zone).iso8601,
        minutes: reservation.minutes,
        room_name: reservation.room.name,
        room_id: reservation.room_id,
        user_name: reservation.user.name,
        note: reservation.note
      }
    end

    render json: reservation_details
  rescue ArgumentError => e
    render json: { error: "Invalid date format" }, status: :unprocessable_entity
  end

  private

  def find_reservation(key = :id)
    @reservation = Reservation.for_location_id(current_location&.id).find(params[key])
  end

  def set_reserved_user
    if staff
      @user = User.for_space(current_tenant).find_by(id: params[:user_id]) || current_user
    else
      @user = current_user
    end
  end

  def staff
    return false unless current_user.present?
    current_user.admin_of_location?(current_location) || current_user.general_manager_of_location?(current_location) || current_user.community_manager_of_location?(current_location)
  end

  # Reserve Now — instant booking flow

  def reserve_now
    include_stripe
    background_image

    unless current_location
      flash[:error] = "Please select a location first."
      redirect_to home_path
      return
    end

    zone = ActiveSupport::TimeZone[current_location.time_zone] || Time.zone
    now = Time.current.in_time_zone(zone)

    # Round up to next 15-minute mark
    remainder = now.min % 15
    @start_time = remainder == 0 ? now : now + (15 - remainder).minutes
    @start_time = @start_time.change(sec: 0)

    @duration = current_user.preferred_meeting_duration.to_i
    @duration = 60 if @duration <= 0
    @day_or_night = @start_time.hour >= 12 ? "night" : "day"

    # Find available rooms right now for the preferred duration
    all_visible = current_location.rooms.visible
    available = current_location.rooms.available(
      date: @start_time.to_date.to_s,
      time: @start_time.strftime("%H:%M"),
      duration: @duration
    )

    can_see_all = current_user.can_see_all_rooms?(current_location, @start_time.to_date)

    # Filter to rooms the user can see
    if !can_see_all
      available = available.rentable
    end

    # Force query evaluation so empty? check is accurate after filtering
    available_rooms_list = available.to_a

    Rails.logger.info("[ReserveNow] visible=#{all_visible.count} available=#{available_rooms_list.count} can_see_all=#{can_see_all} time=#{@start_time} duration=#{@duration} user=#{current_user.id} admin=#{current_user.admin?}")

    if available_rooms_list.empty?
      # Track demand miss
      RoomDemandMiss.create!(
        user: current_user,
        operator: current_tenant,
        location: current_location,
        missed_at: now,
        day_of_week: now.wday,
        hour_of_day: now.hour
      )
      SendNotificationsJob.perform_later(RoomDemandMiss.last)

      # Get all rooms with their next free time for display
      @rooms_with_free_times = current_location.rooms.visible.map do |room|
        current_booking = room.reservations.ongoing.first
        next_booking_end = if current_booking
          current_booking.datetime_out
        else
          # Room might be booked starting now — find the current overlapping reservation
          overlap = room.reservations.overlapping(@start_time, @start_time + @duration.minutes).order(:datetime_in).first
          overlap&.datetime_out
        end
        { room: room, free_at: next_booking_end }
      end.sort_by { |r| r[:free_at] || Time.current }

      render :no_rooms_available
      return
    end

    # Pick the best room
    preferred = available_rooms_list.find { |r| r.id == current_user.preferred_room_id }
    @room = preferred || available_rooms_list.min_by { |r| r.hourly_rate_in_cents.to_i } || available_rooms_list.first

    unless @room
      flash[:error] = "No rooms available right now."
      redirect_to calendar_reservations_path
      return
    end

    available_ids = available_rooms_list.map(&:id)
    @available_rooms = available_rooms_list.reject { |r| r.id == @room.id }.sort_by { |r| r.hourly_rate_in_cents.to_i }
    @unavailable_rooms = current_location.rooms.visible.where.not(id: available_ids)

    # Calculate pricing
    compute_reserve_now_pricing

    # Max duration for slider
    @max_duration = [@room.calculate_max_continuous_duration(start_time: @start_time), 240].min
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "Unable to load Reserve Now: #{e.message}"
    redirect_to calendar_reservations_path
  end

  def reserve_now_price
    room = current_location.rooms.find(params[:room_id])
    duration = params[:duration].to_i
    date = Time.zone.parse(params[:date])

    should_charge = current_user.should_charge_for_reservation?(current_location, date)
    hourly_price = room.hourly_rate_in_cents / 100.0
    total_price = hourly_price * (duration / 60.0)

    # Check subscription overage
    begin
      sub_info = current_user.subscription_reservation_charge_info(current_location, duration)
    rescue => e
      sub_info = nil
    end

    # Check day pass overage
    begin
      dp_info = current_user.day_pass_reservation_charge_info(current_location, date.to_date, duration)
    rescue => e
      dp_info = nil
    end

    included = !should_charge && room.hourly_rate_in_cents > 0
    if sub_info && sub_info[:charge_type] == :partial_overage
      included = false
      total_price = sub_info[:overage_amount_in_cents] / 100.0
    end
    if dp_info && dp_info[:charge_type] == :partial_overage
      included = false
      total_price = dp_info[:overage_amount_in_cents] / 100.0
    end

    render json: {
      should_charge: should_charge || (sub_info&.dig(:charge_type) == :partial_overage) || (dp_info&.dig(:charge_type) == :partial_overage),
      included: included,
      total_price: total_price,
      hourly_price: hourly_price,
      included_minutes_remaining: sub_info&.dig(:included_minutes_remaining) || dp_info&.dig(:included_minutes_remaining),
    }
  end

  private

  def compute_reserve_now_pricing
    @should_charge = current_user.should_charge_for_reservation?(current_location, @start_time.to_date)
    @hourly_price = @room.hourly_rate_in_cents / 100.0
    @total_price = @hourly_price * (@duration / 60.0)

    begin
      @subscription_charge_info = current_user.subscription_reservation_charge_info(current_location, @duration)
    rescue => e
      @subscription_charge_info = nil
    end

    begin
      @day_pass_charge_info = current_user.day_pass_reservation_charge_info(current_location, @start_time.to_date, @duration)
    rescue => e
      @day_pass_charge_info = nil
    end

    @included_in_plan = !@should_charge && @room.hourly_rate_in_cents > 0
    if @subscription_charge_info && @subscription_charge_info[:charge_type] == :partial_overage
      @included_in_plan = false
      @total_price = @subscription_charge_info[:overage_amount_in_cents] / 100.0
    end
    if @day_pass_charge_info && @day_pass_charge_info[:charge_type] == :partial_overage
      @included_in_plan = false
      @total_price = @day_pass_charge_info[:overage_amount_in_cents] / 100.0
    end

    @included_minutes_remaining = @subscription_charge_info&.dig(:included_minutes_remaining) || @day_pass_charge_info&.dig(:included_minutes_remaining)
  end

  public

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
    @datetime_in = zone.local(@day.year, @day.month, @day.day, @hour.hour, @hour.min)
  end
end
