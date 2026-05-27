class Api::V1::Admin::ReservationsController < Api::V1::Admin::BaseController
  def index
    reservations = Reservation.unscoped
                              .joins(:room)
                              .where(rooms: { operator_id: current_tenant.id })
                              .where(cancelled: false)

    reservations = apply_scope(reservations, params[:scope])
    reservations = reservations.order(:datetime_in).limit(30).offset(params[:offset].to_i)

    render json: reservations.includes(:room, :user).map { |r| reservation_json(r) }
  end

  def calendar
    start_date = Time.zone.parse(params[:start])
    end_date = Time.zone.parse(params[:end])

    reservations = Reservation.unscoped
                              .joins(:room)
                              .where(rooms: { operator_id: current_tenant.id })
                              .where(cancelled: false)
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
    room = Room.find(params[:room_id])
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
      render_error(result.error || 'Booking failed')
    end
  end

  def extend
    reservation = Reservation.unscoped
                             .joins(:room)
                             .where(rooms: { operator_id: current_tenant.id })
                             .find(params[:id])

    additional_minutes = params[:additional_minutes].to_i
    return render_error('Invalid duration') if additional_minutes <= 0

    # Same conflict check the member-side extend runs — no booking may
    # start in the extension window.
    unless reservation.room.available?(start_time: reservation.datetime_out, duration: additional_minutes)
      return render_error('Room is not available for that extension')
    end

    # Route through the same interactor as the member-side endpoint so
    # billing fires: post-start extensions hit ChargeExtensionDelta
    # (auto-capture for the additional cost); pre-start extensions go
    # through AuthorizeHoldOrSchedule (replaces the existing hold or
    # stays deferred). Bypassing this previously gave members free time
    # when an admin extended a captured booking.
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
  rescue => e
    render_error(e.message)
  end

  def destroy
    reservation = Reservation.unscoped
                             .joins(:room)
                             .where(rooms: { operator_id: current_tenant.id })
                             .find(params[:id])

    return render json: { success: true } if reservation.cancelled?

    location = reservation.room.location
    creds = { api_key: location.stripe_secret_key, stripe_account: location.stripe_user_id }

    reservation.with_lock do
      Reservation.unscoped { reservation.reload }
      return render json: { success: true } if reservation.cancelled?

      reservation.update!(cancelled: true)

      if reservation.stripe_payment_intent_id.present?
        if reservation.captured_at.present?
          # Already captured — find the local invoice and refund it
          # via the existing refund pipeline. Admin can refund any
          # extension-delta invoices separately from the invoices list.
          invoice = Invoice.find_by(stripe_payment_intent_id: reservation.stripe_payment_intent_id)
          if invoice && !invoice.refunded?
            begin
              Billing::Invoices::Refunds::Create.call(
                operator: current_tenant,
                invoice: RefundableFactory.for(invoice),
                location: location,
              )
            rescue => e
              Rails.logger.warn("Admin cancel: refund failed for invoice #{invoice.id}: #{e.class}: #{e.message}")
              Honeybadger.notify(e, context: { reservation_id: reservation.id, invoice_id: invoice.id })
            end
          end
        else
          # Pre-capture — void the held PaymentIntent so the member's
          # card isn't kept frozen until Stripe expires the auth.
          begin
            Stripe::PaymentIntent.cancel(reservation.stripe_payment_intent_id, {}, creds)
          rescue Stripe::InvalidRequestError => e
            Rails.logger.warn("Admin cancel: PI release failed (#{e.message}) reservation=#{reservation.id}")
          end
        end
      end
    end

    render json: { success: true }
  end

  private

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
