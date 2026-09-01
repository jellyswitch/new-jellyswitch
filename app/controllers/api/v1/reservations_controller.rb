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
    # Scope to the caller's operator (mirrors #update below) — a bare Room.find
    # is global in the API, letting a member book a foreign operator's room.
    room = current_tenant.rooms.find_by(id: params[:reservation][:room_id])
    return render_error("Room not found", status: :not_found) unless room

    datetime_in = parse_local_datetime(params[:reservation][:datetime_in], room)
    minutes = params[:reservation][:minutes].to_i
    date = datetime_in.to_date

    # Duration backstop — the UI sliders enforce the same policy (staff 12h;
    # priced rooms 12h; free rooms 4h), this catches hand-rolled requests.
    duration_cap = room.max_bookable_minutes(admin: staff_booker?)
    if minutes > duration_cap
      return render_error("#{room.name} can be booked for up to #{duration_cap / 60} hours.")
    end

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

    # Included-room coverage (ADR 0019): booking an included room commits a day
    # pass for its date, chosen by the member BEFORE booking. The organizer's
    # coverage steps (ReuseCoveragePass / RedeemBundlePass / BuyCoverageDayPass)
    # act on the decision flag; EnforceCoverage 422s an uncovered included
    # booking. The old silent auto-buy is gone (it charged for a fresh single
    # pass even when the member held a bundle).
    user = current_api_user
    location = current_location
    use_bundle_pass   = ActiveModel::Type::Boolean.new.cast(params.dig(:reservation, :use_bundle_pass))
    use_existing_pass = ActiveModel::Type::Boolean.new.cast(params.dig(:reservation, :use_existing_pass))
    buy_day_pass      = ActiveModel::Type::Boolean.new.cast(params.dig(:reservation, :buy_day_pass))

    # Coverage for the ROOM's location (bundles/passes resolve off room.location).
    coverage = Billing::Reservations::CoverageState.for(user: user, room: room, date: date, location: location)
    coverage_day_pass_type = coverage.day_pass_type

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
        attendee_count: params.dig(:reservation, :attendee_count).presence,
      },
      user: current_api_user,
      location: current_location,
      day_pass_charge_info: day_pass_charge_info,
      subscription_charge_info: subscription_charge_info,
      use_bundle_pass: use_bundle_pass,
      use_existing_pass: use_existing_pass,
      buy_day_pass: buy_day_pass,
      day_pass_type: coverage_day_pass_type,
      enforce_coverage: true, # member self-service: ADR 0019 block-if-uncovered
      enforce_posted_hours: true, # member self-service: bookings stay inside posted hours
      enforce_payment_standing: true, # non-payment cutoff (PaymentCutoff); no-op for staff
    )

    if result.success?
      render json: reservation_json(result.reservation), status: :created
    elsif result.conflict
      render_conflict(result.message.presence || 'That room was just booked.', result.reservation)
    else
      render_error(result.message.presence || result.error || 'Booking failed')
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
    if reservation.datetime_in <= Time.current
      return render_error('This reservation has already started, so it can no longer be changed — you can end it early to free the room.')
    end
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

    duration_cap = new_room.max_bookable_minutes(admin: staff_booker?)
    if new_minutes > duration_cap
      return render_error("#{new_room.name} can be booked for up to #{duration_cap / 60} hours.")
    end

    # Posted-hours backstop on MOVES too — otherwise an in-hours booking could
    # be edited into the middle of the night and re-open the door via the
    # reservation ±window (mirrors EnforcePostedHours on create).
    if (hours_error = posted_hours_violation(new_room, new_datetime_in, new_minutes))
      return render_error(hours_error)
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
    elsif result.conflict
      # The failed save left the new attrs assigned in-memory, so
      # window_label reflects the REQUESTED window, not the old one.
      render_conflict(result.error.presence || 'That room was just booked.', reservation)
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

    # A Day Office hold is not a booking the member made — it's the office their
    # pass entitles them to, allocated by DayOffices::Allocator (ADR 0026).
    # Cancelling it here would release the room while leaving the pass sold and
    # spent, so the member would still be charged for an office they no longer
    # have. Changing or refunding the PASS is the staff-side operation.
    # Checked before the cutoff guard so the member gets this reason rather
    # than a timing one.
    if reservation.day_office_hold?
      return render_error('Your office comes with your Day Office pass — ask staff to change or refund it.')
    end

    # Two refusals with different fixes for the member: a reservation that
    # already STARTED can still be ended early (elapsed time counts, the
    # rest frees up), while one starting within the cutoff is simply
    # committed. The old single message told a member mid-session their
    # booking "starts within a minute" — nonsense that read as a bug and
    # invited retries (member_feedback 24800).
    if reservation.datetime_in <= Time.current
      return render_error('This reservation has already started, so it can no longer be cancelled — you can end it early instead.')
    end
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
      # Does the room have space right after this reservation? An extension
      # must also stay inside posted hours for hour-bounded users, so those
      # options gray out instead of failing at extend_time.
      available = room.available?(start_time: reservation.datetime_out, duration: additional) &&
                  posted_hours_violation(room, reservation.datetime_in, reservation.minutes + additional).nil?

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

    # Posted-hours backstop: an extension may not run past close for
    # hour-bounded users (day-pass guests). Members/leaseholders/staff are
    # exempt inside posted_hours_violation.
    if (hours_error = posted_hours_violation(reservation.room, reservation.datetime_in,
                                             reservation.minutes + additional))
      return render_error(hours_error)
    end

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
      access_opens_label: r.access_opens_at.strftime("%l:%M %p").strip,
      access_window_minutes: r.building_access_window_minutes,
      duration: "#{r.minutes} min",
      minutes: r.minutes,
      minutes_remaining: minutes_remaining,
      # "The reservation is the key" (ADR 0021). room_door_unlockable is the
      # optimistic client signal (ongoing, or starting within the grace);
      # the unlock endpoint re-checks for a still-occupying prior booking.
      room_door_id: room_door(r)&.id,
      room_door_name: room_door(r)&.name,
      room_door_unlockable: !r.cancelled && room_door(r).present? &&
        (ongoing || (future && r.datetime_in <= now + Door::ROOM_LOCK_EARLY_GRACE)),
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

  # The room's electric lock (ADR 0021), if it has a Kisi-openable one.
  # Memoized per room id — reservation_json runs in a list loop — via fetch
  # so a nil result (most rooms have no lock) is cached too, not re-queried.
  # order(:id) keeps the pick deterministic when a room has two locks.
  def room_door(r)
    @room_doors ||= {}
    @room_doors.fetch(r.room_id) do
      @room_doors[r.room_id] = r.room.doors.where(available: true).where.not(kisi_id: nil).order(:id).first
    end
  end

  # Staff get the 12h admin booking cap on every surface.
  def staff_booker?
    current_api_user.admin_or_manager?(current_location) || current_api_user.superadmin?
  end

  # Returns an error string when a member self-serve booking window falls
  # outside the room location's posted hours; nil when allowed. Members,
  # leaseholders, superadmins (books_outside_posted_hours?) and location staff
  # are exempt — the same rule Billing::Reservations::EnforcePostedHours
  # applies on create. Used by the update (move) and extend paths.
  def posted_hours_violation(room, datetime_in, minutes)
    location = room&.location || current_location
    return nil if location.nil?
    return nil if staff_booker? || current_api_user.books_outside_posted_hours?(location)

    # Time-of-day bound only (within_posted_hours?), matching
    # EnforcePostedHours — the open_<day> flags mark staffed days and don't
    # bound self-serve bookings. end - 1 minute so a booking ending exactly
    # at close passes.
    return nil if location.within_posted_hours?(datetime_in) &&
                  location.within_posted_hours?(datetime_in + minutes.minutes - 1.minute)

    "#{location.name} is open #{location.posted_hours_label}. Rooms can be booked during open hours."
  end

  # 409 for a room-time overlap. `error` doubles as the display sentence for
  # old app bundles that render data.error raw; `conflict` lets new bundles
  # style the "Just missed it" alert + refresh. `failed_reservation` is the
  # unsaved record carrying the requested room/window.
  def render_conflict(message, failed_reservation)
    render json: {
      error: message,
      conflict: {
        room_name: failed_reservation&.room&.name,
        window_label: failed_reservation&.window_label,
      },
    }, status: :conflict
  end
end
