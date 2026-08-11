class Api::V1::Admin::ReservationsController < Api::V1::Admin::BaseController
  def index
    reservations = visible_reservations

    reservations = apply_scope(reservations, params[:scope])
    reservations = reservations.order(:datetime_in).limit(30).offset(params[:offset].to_i)

    render json: reservations.includes(:room, :user).map { |r| reservation_json(r) }
  end

  def calendar
    start_date = Time.zone.parse(params[:start])
    end_date = Time.zone.parse(params[:end])

    reservations = visible_reservations
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
    room = find_room
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
      # Billing interactors fail with `context.message` (e.g. an overlap
      # conflict). Surface that so the admin sees the real reason rather
      # than a blanket "Booking failed".
      render_error(result.message || result.error || 'Booking failed')
    end
  rescue ActiveRecord::RecordNotFound
    render_error('Not found', status: :not_found)
  end

  def extend
    reservation = find_reservation

    additional_minutes = params[:additional_minutes].to_i
    return render_error('Invalid duration') if additional_minutes <= 0

    # Same conflict check the member-side extend runs — no booking may
    # start in the extension window.
    unless reservation.room.available?(start_time: reservation.datetime_out, duration: additional_minutes)
      return render_error('Room is not available for that extension')
    end

    # Route through the same interactor as the member-side endpoint so
    # billing fires: under capture-at-booking every extension is a delta charge
    # via ChargeExtensionDelta (auto-capture for the additional cost). Bypassing
    # this previously gave members free time when an admin extended a booking.
    result = Billing::Reservations::ExtendReservation.call(
      reservation: reservation,
      additional_duration: additional_minutes,
      user: reservation.user,
    )

    if result.success?
      render json: { success: true, new_duration: reservation.reload.minutes }
    else
      render_error(result.message || 'Could not extend reservation')
    end
  rescue ActiveRecord::RecordNotFound
    render_error('Reservation not found', status: :not_found)
  rescue => e
    render_error(e.message)
  end

  def destroy
    reservation = find_reservation

    return render json: { success: true } if reservation.cancelled?

    # Capture-at-booking (ADR 0010/0011): an admin cancel refunds ALL of the
    # reservation's invoices (booking capture + any extension deltas) regardless
    # of the cancellation window, via the one unified pipeline.
    result = CancelReservation.call(reservation: reservation, mode: :admin)
    unless result.success?
      return render_error(result.message || 'Could not cancel reservation')
    end

    render json: { success: true }
  rescue ActiveRecord::RecordNotFound
    render_error('Reservation not found', status: :not_found)
  end

  # Day Office admin reassign (Task 12, ADR 0026): move a live hold to any
  # other active room at its location, hidden included. Goes through the same
  # find_reservation lookup extend/destroy use, so the boundary is identical
  # and can't drift: a cross-TENANT id 404s, and (since #717) so does a
  # cross-LOCATION one — non-superadmin staff can only move holds at the
  # locations they manage. The target room needs no location filter of its
  # own: ReassignRoom refuses any room whose location_id differs from the
  # hold's, and the hold is already confined to an allowed location.
  def reassign_room
    hold = find_reservation
    room = current_tenant.rooms.active.find_by(id: params[:room_id])

    result = DayOffices::ReassignRoom.call(hold: hold, room: room)
    return render_error(result.error) unless result.ok?

    render json: { success: true, room: hold.reload.room.name }
  rescue ActiveRecord::RecordNotFound
    render_error("Reservation not found", status: :not_found)
  end

  # Free active rooms at the hold's location for its exact window — what the
  # reassign picker offers. hidden mirrors Room#visible inverted so the admin
  # UI can badge a hidden-but-usable room instead of hiding it outright
  # (decision #8: hidden rooms are fair game for an admin-driven move). The
  # candidate query itself lives in DayOffices::ReassignRoom.options_for
  # (Task 14) so the web profile's Reassign select can't drift from this list.
  def reassign_options
    hold = find_reservation
    # Duplicated from ReassignRoom's own guard: this action never calls the
    # service (it only lists candidates), so it needs the same liveness
    # check to give the same clear refusal instead of listing options for a
    # hold that can no longer be moved.
    return render_error("That office hold is no longer active.") if hold.cancelled? || hold.datetime_out <= Time.current
    return render_error("Not a Day Office hold.") unless hold.day_office_hold?

    rooms = DayOffices::ReassignRoom.options_for(hold)

    render json: rooms.map { |r| { id: r.id, name: r.name, hidden: !r.visible } }
  rescue ActiveRecord::RecordNotFound
    render_error("Reservation not found", status: :not_found)
  end

  private

  # Base relation for the list endpoints (index/calendar). Operator-wide was
  # not the right boundary here either: once find_reservation confined
  # destroy/extend to allowed_location_ids, a location-scoped community
  # manager still SAW every other location's bookings (member names, times)
  # in these lists — rows the web list (current_location-scoped) never shows
  # them and that they could no longer act on. Same superadmin bypass as
  # find_reservation, so superadmins keep the operator-wide view the mobile
  # Reservations screen and calendar have today.
  def visible_reservations
    scope = Reservation.unscoped
                       .joins(:room)
                       .where(rooms: { operator_id: current_tenant.id })
                       .where(cancelled: false)
    scope = scope.where(rooms: { location_id: allowed_location_ids }) unless current_api_user.superadmin?
    scope
  end

  # Room lookup for create. This was a bare Room.find — acts_as_scopable's
  # default_scope reads RequestStore, which only the web Operator:: stack
  # sets, so in the API the lookup was completely unscoped and an admin
  # could book (and charge their member for) a room in a DIFFERENT
  # OPERATOR. Tenant-scope via the association, then confine non-superadmins
  # to the same location set find_reservation uses.
  def find_room
    scope = current_tenant.rooms
    scope = scope.where(location_id: allowed_location_ids) unless current_api_user.superadmin?
    scope.find(params[:room_id])
  end

  # Lookup for the mutating actions (destroy/extend). Tenant scope alone is
  # not the boundary the web enforces: operator destroy/extend resolve via
  # Reservation.for_location_id(current_location) + Pundit admin_or_manager?,
  # so a community manager homed at location B can never cancel a location-A
  # booking there — but this lookup only checked rooms.operator_id, so they
  # could here. Confine non-superadmins to the same location set
  # enforce_location_scope! uses (managed locations + home). Stays .unscoped
  # because destroy's already-cancelled early return must still find
  # cancelled rows past the model's default_scope — and the Day Office
  # reassign actions need that same reach for their own reason: they must be
  # able to FIND a cancelled/ended hold so ReassignRoom's liveness guard can
  # answer with a clear "no longer active" 422, instead of a bare 404 that
  # would look identical to "wrong id".
  def find_reservation
    scope = Reservation.unscoped
                       .joins(:room)
                       .where(rooms: { operator_id: current_tenant.id })
    scope = scope.where(rooms: { location_id: allowed_location_ids }) unless current_api_user.superadmin?
    scope.find(params[:id])
  end

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
      cancelled: r.cancelled,
      # Same blast radius as the admin members#reservations fix: without
      # this field the AdminReservationsScreen list rendered ended-early
      # bookings identically to active ones (and offered Extend/Cancel
      # buttons), so admins couldn't tell whether the room was actually
      # still occupied.
      ended_early: r.ended_early,
    }
  end
end
