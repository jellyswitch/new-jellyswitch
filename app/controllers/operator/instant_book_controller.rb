class Operator::InstantBookController < Operator::BaseController
  def index
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

    # Query available rooms directly
    end_time = @start_time + @duration.minutes
    booked_room_ids = Reservation.where(room: current_location.rooms.visible)
      .where("datetime_in < ? AND (datetime_in + minutes * interval '1 minute') > ?", end_time, @start_time)
      .where(cancelled: false)
      .pluck(:room_id)
      .uniq

    available = current_location.rooms.visible.where.not(id: booked_room_ids)

    if !current_user.can_see_all_rooms?(current_location, @start_time.to_date)
      # ADR 0019: include day-pass-unlockable rooms so a not-yet-covered member
      # can pick one and get the buy-a-day-pass confirm (parity with mobile).
      available = available.rentable_or_day_pass_included
    end

    available_rooms_list = available.to_a

    if available_rooms_list.empty?
      RoomDemandMiss.create!(
        user: current_user,
        operator: current_tenant,
        location: current_location,
        missed_at: now,
        day_of_week: now.wday,
        hour_of_day: now.hour
      )

      @rooms_with_free_times = current_location.rooms.visible.map do |room|
        current_booking = room.reservations.ongoing.first
        overlap = room.reservations.overlapping(@start_time, @start_time + @duration.minutes).order(:datetime_in).first unless current_booking
        free_at = current_booking&.datetime_out || overlap&.datetime_out
        { room: room, free_at: free_at }
      end.sort_by { |r| r[:free_at] || Time.current }

      # No background image — white background
      render :no_rooms_available
      return
    end

    # Pick the best room
    preferred = available_rooms_list.find { |r| r.id == current_user.preferred_room_id }
    @room = preferred || available_rooms_list.min_by { |r| r.hourly_rate_in_cents.to_i } || available_rooms_list.first

    available_ids = available_rooms_list.map(&:id)
    @available_rooms = available_rooms_list.reject { |r| r.id == @room.id }.sort_by { |r| r.hourly_rate_in_cents.to_i }
    @unavailable_rooms = current_location.rooms.visible.where.not(id: available_ids)

    # Calculate pricing
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

    # Max duration for slider
    @max_duration = [@room.calculate_max_continuous_duration(start_time: @start_time), 240].min

    include_stripe
    background_image
  end

  def price
    room = current_location.rooms.find(params[:room_id])
    duration = params[:duration].to_i
    date = Time.zone.parse(params[:date])

    should_charge = current_user.should_charge_for_reservation?(current_location, date)
    hourly_price = room.hourly_rate_in_cents / 100.0
    total_price = hourly_price * (duration / 60.0)

    begin
      sub_info = current_user.subscription_reservation_charge_info(current_location, duration)
    rescue => e
      sub_info = nil
    end

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

    # ADR 0019: coverage state + prospective overage for the pre-booking confirm.
    coverage = Billing::Reservations::CoverageState.for(user: current_user, room: room, date: date.to_date, location: current_location)
    covering_type = case coverage.outcome
                    when :bundle_available then coverage.bundle&.day_pass_type
                    when :reusable_pass    then coverage.reusable_pass&.day_pass_type
                    when :needs_purchase   then coverage.day_pass_type
                    else current_user.day_passes.for_location(current_location).for_day(date.to_date).first&.day_pass_type
                    end

    render json: {
      should_charge: should_charge || (sub_info&.dig(:charge_type) == :partial_overage) || (dp_info&.dig(:charge_type) == :partial_overage),
      included: included,
      total_price: total_price,
      hourly_price: hourly_price,
      included_minutes_remaining: sub_info&.dig(:included_minutes_remaining) || dp_info&.dig(:included_minutes_remaining),
      coverage: {
        state: coverage.outcome,
        bundle_passes_remaining: coverage.passes_remaining,
        day_pass_amount_in_cents: coverage.amount_cents,
        reusable_from_date: coverage.reusable_pass&.day&.iso8601,
        overage_in_cents: Billing::Reservations::OveragePreview.cents(
          user: current_user, location: current_location, date: date.to_date, minutes: duration, day_pass_type: covering_type),
      },
    }
  end
end
