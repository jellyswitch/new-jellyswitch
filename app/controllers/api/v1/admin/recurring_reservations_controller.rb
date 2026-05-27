class Api::V1::Admin::RecurringReservationsController < Api::V1::Admin::BaseController
  def index
    recurring = RecurringReservation.where(operator: current_tenant)
      .order(created_at: :desc)

    render json: recurring.map { |r|
      {
        id: r.id,
        room_name: r.room&.name,
        user_name: r.user&.name,
        # The wday integer is kept for backward-compat with older mobile
        # builds that still render `item.day_of_week`. New builds should
        # prefer `pattern_description`, which is human-readable for every
        # supported pattern (Daily, Weekdays, Every Monday, Every other
        # Monday, Monthly on the 1st, Every other month on the 14th).
        day_of_week: r.day_of_week,
        recurrence_pattern: r.recurrence_pattern,
        pattern_description: r.pattern_description,
        time: r.time_of_day&.strftime("%l:%M %p")&.strip,
        duration: r.duration_minutes,
        active: !r.cancelled,
      }
    }
  end

  def create
    recurring = RecurringReservation.new(recurring_params)
    recurring.operator = current_tenant
    recurring.location = current_location

    if recurring.save
      # Generate reservation occurrences. Reservation has no operator/
      # location columns of its own — those are derived through the
      # associated room — so passing them here used to raise
      # ActiveModel::UnknownAttributeError. The recurring-create flow
      # had been sitting on this latent bug because the mobile was
      # never sending a valid payload (missing recurrence_pattern et
      # al.), so `recurring.save` failed before we reached this loop.
      recurring.occurrence_dates.each do |date|
        datetime_in = date.to_datetime.change(
          hour: recurring.time_of_day.hour,
          min:  recurring.time_of_day.min,
        )
        recurring.reservations.create(
          user:        recurring.user,
          room:        recurring.room,
          datetime_in: datetime_in,
          minutes:     recurring.duration_minutes,
        )
      end

      render json: { id: recurring.id, room_name: recurring.room&.name }, status: :created
    else
      render_error(recurring.errors.full_messages.join(', '))
    end
  end

  def destroy
    recurring = RecurringReservation.find(params[:id])
    recurring.update!(cancelled: true)
    recurring.future_reservations.update_all(cancelled: true)

    render json: { success: true }
  end

  def cancel_occurrence
    recurring = RecurringReservation.find(params[:id])
    date = Date.parse(params[:date])

    reservation = recurring.reservations
      .where(cancelled: false)
      .where(datetime_in: date.all_day)
      .first

    if reservation
      reservation.update!(cancelled: true)
      render json: { success: true }
    else
      render_error("No reservation found for that date", status: :not_found)
    end
  end

  private

  def recurring_params
    params.permit(:user_id, :room_id, :title, :recurrence_pattern,
      :duration_minutes, :time_of_day, :start_date, :end_date,
      :day_of_week, :day_of_month)
  end
end
