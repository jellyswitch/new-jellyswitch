class Operator::RecurringReservationsController < Operator::BaseController
  before_action :background_image

  def index
    authorize :recurring_reservation
    @recurring_reservations = RecurringReservation.where(location: current_location)
                                                   .active
                                                   .includes(:room, :user)
                                                   .order(created_at: :desc)
  end

  def show
    @recurring_reservation = RecurringReservation.find(params[:id])
    authorize @recurring_reservation
    @upcoming_reservations = @recurring_reservation.reservations.future.order(:datetime_in)
    @past_reservations = @recurring_reservation.reservations.past.order(datetime_in: :desc).limit(10)
  end

  def new
    authorize :recurring_reservation
    @rooms = current_location.rooms.visible.order(:name)
    @members = User.lease_options_for_select(current_tenant, current_location)
  end

  def create
    authorize :recurring_reservation

    room = current_location.rooms.find(params[:room_id])
    member = current_tenant.users.find(params[:user_id])

    # Parse time
    time_of_day = Time.parse(params[:time_of_day])

    # Calculate end date from period
    start_date = Date.parse(params[:start_date])
    period_months = params[:period_months].to_i
    end_date = start_date + period_months.months

    result = RecurringReservations::Create.call(
      user: member,
      room: room,
      title: params[:title],
      recurrence_pattern: params[:recurrence_pattern],
      duration_minutes: params[:duration_minutes].to_i,
      time_of_day: time_of_day,
      day_of_week: params[:day_of_week].present? ? params[:day_of_week].to_i : nil,
      day_of_month: params[:day_of_month].present? ? params[:day_of_month].to_i : nil,
      start_date: start_date,
      end_date: end_date
    )

    if result.success?
      flash[:notice] = "Recurring reservation created! #{result.recurring_reservation.reservations.count} meetings scheduled."
      redirect_to recurring_reservation_path(result.recurring_reservation)
    else
      flash[:alert] = result.message
      @conflicts = result.conflicts
      @rooms = current_location.rooms.visible.order(:name)
      @members = User.lease_options_for_select(current_tenant, current_location)
      render :new
    end
  end

  def check_conflicts
    authorize :recurring_reservation

    room = current_location.rooms.find(params[:room_id])
    time_of_day = Time.parse(params[:time_of_day])
    start_date = Date.parse(params[:start_date])
    period_months = params[:period_months].to_i
    end_date = start_date + period_months.months

    recurring = RecurringReservation.new(
      room: room,
      recurrence_pattern: params[:recurrence_pattern],
      duration_minutes: params[:duration_minutes].to_i,
      time_of_day: time_of_day,
      day_of_week: params[:day_of_week].present? ? params[:day_of_week].to_i : nil,
      day_of_month: params[:day_of_month].present? ? params[:day_of_month].to_i : nil,
      start_date: start_date,
      end_date: end_date
    )

    dates = recurring.occurrence_dates
    zone = ActiveSupport::TimeZone[room.location.time_zone] || Time.zone

    # Batch-fetch existing reservations for conflict checking
    if dates.any?
      range_start = zone.local(dates.first.year, dates.first.month, dates.first.day, 0, 0)
      range_end = zone.local(dates.last.year, dates.last.month, dates.last.day, 23, 59)
      existing = room.reservations.where(cancelled: false)
                     .overlapping(range_start, range_end + 1.day)
                     .pluck(:datetime_in, :minutes)
    else
      existing = []
    end

    @dates_with_status = dates.map do |date|
      start_time = zone.local(date.year, date.month, date.day,
                              time_of_day.hour, time_of_day.min)
      end_time = start_time + params[:duration_minutes].to_i.minutes

      has_conflict = existing.any? do |res_start, res_minutes|
        res_end = res_start + res_minutes.minutes
        start_time < res_end && end_time > res_start
      end

      { date: date, time: start_time, conflict: has_conflict }
    end

    render partial: "conflict_results", locals: { dates_with_status: @dates_with_status }
  end

  def cancel_series
    @recurring_reservation = RecurringReservation.find(params[:id])
    authorize @recurring_reservation

    result = RecurringReservations::CancelSeries.call(
      recurring_reservation: @recurring_reservation
    )

    if result.success?
      flash[:notice] = "Recurring series cancelled. #{result.cancelled_count} reservation(s) affected."
    else
      flash[:alert] = result.message
    end

    redirect_to recurring_reservations_path
  end

  def cancel_occurrence
    @recurring_reservation = RecurringReservation.find(params[:id])
    authorize @recurring_reservation

    reservation = @recurring_reservation.reservations.find(params[:reservation_id])
    reservation.update!(cancelled: true)

    flash[:notice] = "Reservation on #{reservation.datetime_in.strftime('%B %d, %Y')} cancelled."
    redirect_to recurring_reservation_path(@recurring_reservation)
  end

  private

  def background_image
    @background_image = false
  end
end
