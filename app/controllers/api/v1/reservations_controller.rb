class Api::V1::ReservationsController < Api::V1::BaseController
  def index
    user = current_api_user
    scope = user.reservations.where(cancelled: false)

    ongoing = scope.ongoing.order(:datetime_in)
    ongoing_ids = ongoing.pluck(:id)

    upcoming = scope.where("datetime_in > ?", Time.current).where.not(id: ongoing_ids).order(:datetime_in).limit(20)
    past = scope.where("datetime_in + minutes * interval '1 minute' <= ?", Time.current).order(datetime_in: :desc).limit(10)

    render json: {
      ongoing: ongoing.map { |r| reservation_json(r) },
      upcoming: upcoming.map { |r| reservation_json(r) },
      past: past.map { |r| reservation_json(r) },
      # Upcoming room bookings made by the user's ORG-MATES (same company), so a
      # member can see what their team already has reserved and not double-book.
      team: team_reservations(user).map { |r| reservation_json(r).merge(booked_by: r.user&.name) },
    }
  end

  def create
    room = Room.find(params[:reservation][:room_id])
    datetime_in = parse_local_datetime(params[:reservation][:datetime_in], room)
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

    # Coverage check: auto-purchase a day pass for the reservation date
    # if the user has no active subscription, day pass, or lease. Keeps
    # the "you booked for free without a day pass" gap closed.
    user = current_api_user
    location = current_location
    # Opt-in reserve-time bundle redemption (ADR 0015): "use 1 pass for today".
    # When the booker has an active bundle and opts in, RedeemBundlePass (an
    # organizer step) spends one prepaid pass to cover the booking — so DON'T
    # auto-purchase a fresh day pass on top of it here.
    use_bundle_pass = ActiveModel::Type::Boolean.new.cast(params.dig(:reservation, :use_bundle_pass))
    redeeming_bundle = use_bundle_pass && user.has_active_day_pass_bundle?(location)
    # Paid rooms already charge an hourly rate that covers access —
    # don't bundle a day pass on top.
    is_priced_room = room.hourly_rate_in_cents.to_i > 0
    needs_cov = !is_priced_room &&
                !redeeming_bundle &&
                !user.has_active_subscription? &&
                !user.has_active_day_pass?(date) &&
                !user.has_active_lease?(location) &&
                !user.admin_or_manager?(location) &&
                !user.superadmin?
    if needs_cov
      scope = DayPassType
        .where(operator_id: location.operator_id)
        .where("location_id = ? OR location_id IS NULL", location.id)
        .available
        .where(visible: true)
        .where("amount_in_cents > 0")
        .where.not("name ILIKE ?", "%office%")
      suggested = scope.where(default_for_room_booking: true).first ||
                  scope.order(:amount_in_cents).first
      if suggested.nil?
        return render_error("You need a day pass to book for #{date.strftime('%b %-d')}, but none are available. Please contact the operator.")
      end

      # Require a card on file (or a fresh token in this request).
      unless user.card_added_for_location?(location) || stripe_token.present?
        return render_error("A payment method is required to book a room without a day pass or membership.")
      end

      dp_result = Billing::DayPasses::CreateDayPass.call(
        params: { day: date, day_pass_type: suggested.id, operator: location.operator },
        operator: location.operator,
        location: location,
        user_id: user.id,
        out_of_band: false,
      )
      unless dp_result.success?
        return render_error("Couldn't purchase day pass: #{dp_result.message}")
      end
    end

    day_pass_charge_info = user.day_pass_reservation_charge_info(location, date, minutes, room: room)
    # Date-aware: bill against the period this reservation falls in, so booking
    # for next month draws from next month's fresh meeting-room pool.
    subscription_charge_info = user.subscription_reservation_charge_info(location, minutes, room: room, at: datetime_in)

    # Add-on amenities: accept only ids that are orderable add-ons on THIS
    # room. Free features, other rooms' amenities, and bogus ids are dropped —
    # the server never trusts client-supplied prices or memberships.
    requested_amenity_ids = Array(params.dig(:reservation, :amenity_ids)).map(&:to_i)
    amenity_ids = room.amenities.add_ons.where(id: requested_amenity_ids).pluck(:id)

    result = Billing::Reservations::CreateRoomReservation.call(
      reservation_params: {
        datetime_in: datetime_in,
        hours: minutes / 60.0,
        minutes: minutes,
        room: room,
        amenity_ids: amenity_ids,
      },
      user: current_api_user,
      location: current_location,
      day_pass_charge_info: day_pass_charge_info,
      subscription_charge_info: subscription_charge_info,
      use_bundle_pass: use_bundle_pass,
    )

    if result.success?
      render json: reservation_json(result.reservation), status: :created
    else
      render_error(result.error || 'Booking failed')
    end
  end

  CANCEL_CUTOFF = 1.minute

  # PATCH /api/v1/reservations/:id
  # Body: { reservation: { datetime_in: <iso8601>, minutes: <int> } }
  # Adjusts an upcoming reservation's start time and/or duration. Either
  # field may be omitted to keep its current value. Re-validates the slot
  # (overlap check excludes this reservation itself) and re-prices the hold.
  def update
    reservation = current_api_user.reservations.find(params[:id])

    # Editable until the 1-minute cutoff before start. (Capture now happens AT
    # BOOKING, so captured_at is set immediately and is no longer an editability
    # signal — an edit re-prices via a delta charge; ADR 0010.)
    if reservation.datetime_in <= Time.current + CANCEL_CUTOFF
      return render_error('This reservation can no longer be changed — it starts within a minute.')
    end

    new_minutes = params.dig(:reservation, :minutes).present? ? params[:reservation][:minutes].to_i : reservation.minutes
    return render_error('Invalid duration') if new_minutes <= 0

    new_datetime_in = params.dig(:reservation, :datetime_in).present? ?
      parse_local_datetime(params[:reservation][:datetime_in], reservation.room) :
      reservation.datetime_in

    new_room = if params.dig(:reservation, :room_id).present?
      current_tenant.rooms.find_by(id: params[:reservation][:room_id]) ||
        (return render_error('Room not found', status: :not_found))
    else
      reservation.room
    end

    result = Billing::Reservations::UpdateRoomReservation.call(
      reservation: reservation,
      new_room: new_room,
      new_datetime_in: new_datetime_in,
      new_minutes: new_minutes,
      user: current_api_user,
      location: current_location,
    )

    if result.success?
      render json: reservation_json(reservation.reload)
    else
      render_error(result.error || 'Could not update reservation')
    end
  rescue ActiveRecord::RecordNotFound
    render_error('Reservation not found', status: :not_found)
  end

  def destroy
    # Reservation has default_scope cancelled: false, so a re-cancel of
    # an already-cancelled record raises RecordNotFound here — which we
    # treat as success below.
    reservation = current_api_user.reservations.find(params[:id])

    if reservation.datetime_in <= Time.current + CANCEL_CUTOFF
      return render_error('This reservation can no longer be cancelled — it starts within a minute.')
    end

    # Capture-at-booking (ADR 0010/0011): the money was taken at booking, so a
    # cancel is now a REFUND, not a hold release. Inside the cancellation window
    # the member forfeits the charge (no refund); outside, CancelReservation
    # refunds all the reservation's invoices minus refund_fee_percent.
    # fee_charged_in_cents reports what the member is OUT (kept by the operator),
    # preserving the response contract the app already reads.
    op = current_tenant
    window_hours = op&.try(:cancellation_window_hours).to_i
    fee_pct = op&.try(:refund_fee_percent).to_i
    inside_window = window_hours > 0 && (reservation.datetime_in - Time.current) < window_hours.hours

    charged = reservation.captured_amount_in_cents.to_i
    fee_charged_cents = inside_window ? charged : (charged * fee_pct / 100.0).round

    result = CancelReservation.call(
      reservation: reservation, mode: :member, current_user: current_api_user,
    )
    unless result.success?
      return render_error(result.message || 'Could not cancel reservation')
    end

    render json: {
      success: true,
      late_cancellation: inside_window,
      fee_charged_in_cents: fee_charged_cents,
    }
  rescue ActiveRecord::RecordNotFound
    render_error('Reservation not found', status: :not_found)
  end

  # GET /api/v1/reservations/:id/extension_options
  # Returns available extension durations with pricing.
  def extension_options
    reservation = current_api_user.reservations.find(params[:id])
    room = reservation.room
    user = current_api_user
    location = room.location
    date = reservation.datetime_in.to_date

    # Durations we offer (minutes). Mirror web, but add 15 for finer control.
    possible = [15, 30, 45, 60, 90, 120, 180, 240]

    # Current usage already counts the existing reservation's minutes
    # (because it's stored on the record). We want the charge for the
    # ADDITIONAL minutes only.
    options = possible.map do |additional|
      # Does the room have space right after this reservation?
      available = room.available?(start_time: reservation.datetime_out, duration: additional)

      # Compute price delta for the additional minutes.
      sub_info = user.subscription_reservation_charge_info(location, reservation.minutes + additional, room: room)
      dp_info = user.day_pass_reservation_charge_info(location, date, reservation.minutes + additional, room: room)

      # Existing charge baseline (from already-used minutes):
      existing_sub = user.subscription_reservation_charge_info(location, reservation.minutes, room: room)
      existing_dp = user.day_pass_reservation_charge_info(location, date, reservation.minutes, room: room)

      cost_cents =
        if room.hourly_rate_in_cents.to_i > 0
          # Priced room — day passers always pay full hourly rate for the extra minutes.
          # Subscribers use their plan (overage).
          if sub_info
            (sub_info[:overage_amount_in_cents] || 0) - (existing_sub&.dig(:overage_amount_in_cents) || 0)
          else
            (room.hourly_rate_in_cents * additional / 60.0).round
          end
        elsif sub_info
          (sub_info[:overage_amount_in_cents] || 0) - (existing_sub&.dig(:overage_amount_in_cents) || 0)
        elsif dp_info
          (dp_info[:overage_amount_in_cents] || 0) - (existing_dp&.dig(:overage_amount_in_cents) || 0)
        else
          0
        end

      {
        additional_minutes: additional,
        available: available,
        cost_cents: [cost_cents, 0].max,
        new_end_time: (reservation.datetime_out + additional.minutes).iso8601,
        new_end_time_label: (reservation.datetime_out + additional.minutes).strftime("%-l:%M %p").strip,
        new_total_minutes: reservation.minutes + additional,
      }
    end

    render json: { options: options }
  rescue ActiveRecord::RecordNotFound
    render_error('Reservation not found', status: :not_found)
  end

  # PATCH /api/v1/reservations/:id/extend_time
  # Body: { additional_minutes: int }
  def extend_time
    reservation = current_api_user.reservations.find(params[:id])
    additional = params[:additional_minutes].to_i

    return render_error('Invalid duration') if additional <= 0

    # Conflict check: no booking may start in the extension window.
    unless reservation.room.available?(start_time: reservation.datetime_out, duration: additional)
      return render_error('Room is not available for that extension')
    end

    result = Billing::Reservations::ExtendReservation.call(
      reservation: reservation,
      additional_duration: additional,
      user: current_api_user,
    )

    if result.success?
      render json: reservation_json(reservation.reload)
    else
      render_error(result.message || 'Could not extend reservation')
    end
  rescue ActiveRecord::RecordNotFound
    render_error('Reservation not found', status: :not_found)
  end

  # PATCH /api/v1/reservations/:id/end_now
  def end_now
    reservation = current_api_user.reservations.find(params[:id])
    return render_error('Reservation is not in session') unless reservation.ongoing?

    if reservation.end_now!
      render json: reservation_json(reservation.reload)
    else
      render_error('Could not end reservation')
    end
  rescue ActiveRecord::RecordNotFound
    render_error('Reservation not found', status: :not_found)
  end

  private

  # Parse an incoming datetime in the room/location's local time zone
  # unless the string already carries an explicit offset (ISO w/ Z or
  # +HH:MM). Mobile clients that send "2026-04-22T07:15:00" without a
  # zone would otherwise be interpreted as UTC and the booking would
  # land 7 hours off in Pacific time.
  def parse_local_datetime(raw, room)
    raw = raw.to_s
    tz = room.location&.time_zone.presence || 'UTC'
    if raw =~ /(Z|[+\-]\d\d:?\d\d)$/
      Time.parse(raw)
    else
      ActiveSupport::TimeZone[tz].parse(raw)
    end
  end

  # Upcoming, non-cancelled room reservations made by the current user's
  # org-mates (everyone in the same organization, excluding the user). Scoped to
  # the same operator implicitly (org members all belong to one operator).
  def team_reservations(user)
    org = user.organization
    return Reservation.none unless org

    mate_ids = org.users.where.not(id: user.id).pluck(:id)
    return Reservation.none if mate_ids.empty?

    Reservation.where(user_id: mate_ids, cancelled: false)
               .where("datetime_in > ?", Time.current)
               .order(:datetime_in)
               .limit(25)
  end

  def reservation_json(r)
    now = Time.current
    ongoing = r.ongoing?
    future = r.future?
    ends_at = r.datetime_out
    minutes_remaining = ongoing ? ((ends_at - now) / 60).ceil : nil

    {
      id: r.id,
      room_id: r.room_id,
      room_name: r.room.name,
      room_hourly_rate_in_cents: r.room.hourly_rate_in_cents,
      room_photo_url: (r.room.photo.attached? ? url_for(r.room.photo) : nil rescue nil),
      date: r.datetime_in.strftime("%B %e, %Y"),
      time: r.datetime_in.strftime("%l:%M %p").strip,
      datetime_in: r.datetime_in.iso8601,
      datetime_out: ends_at.iso8601,
      end_time_label: ends_at.strftime("%-l:%M %p").strip,
      duration: "#{r.minutes} min",
      minutes: r.minutes,
      minutes_remaining: minutes_remaining,
      paid: r.paid,
      cancelled: r.cancelled,
      payment_failed: r.payment_failed_at.present?,
      ongoing: ongoing,
      future: future,
      can_extend: (ongoing || future) && !r.cancelled,
      can_cancel: future && !r.cancelled && r.datetime_in > Time.current + CANCEL_CUTOFF,
      can_end_now: ongoing && !r.cancelled,
    }
  end
end
