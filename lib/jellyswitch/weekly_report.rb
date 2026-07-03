class Jellyswitch::WeeklyReport
  include ActionView::Helpers::NumberHelper

  # Room utilization is measured against the business window only:
  # 6am-6pm, Monday-Friday, location-local (60 bookable hours/week).
  BUSINESS_DAY_START_HOUR = 6
  BUSINESS_DAY_END_HOUR = 18
  BUSINESS_WDAYS = (1..5) # Monday..Friday

  attr_reader :week_start, :week_end, :report, :operator, :location, :day_passes, :checkins, :new_active_members, :new_free_members, :rooms, :paid_invoices, :unpaid_invoices, :revenue, :reservations, :paid_reservations, :member_reservations, :management_notes, :questions, :unanswered_questions, :admins, :room_demand_misses

  delegate :active_member_count, :free_member_count, :active_lease_member_count, to: :report

  def initialize(operator, location, week_start, week_end)
    @week_start = week_start
    @week_end = week_end
    @operator = operator
    @location = location

    @report = Jellyswitch::Report.new(operator, location)

    @day_passes = location.day_passes.for_week(@week_start, @week_end).count
    @checkins = location.checkins.for_week(@week_start, @week_end).count

    @new_active_members = Subscription.where(plan: location.plans.individual.nonzero, active: true)
      .for_week(@week_start, @week_end).select(:subscribable_id).distinct.count
    @new_free_members = Subscription.where(plan: location.plans.individual.free, active: true)
      .for_week(@week_start, @week_end).select(:subscribable_id).distinct.count

    reservations_scope = Reservation.where(room: location.rooms).for_week(@week_start, @week_end)
    @reservations = reservations_scope.distinct.count
    # paid: true  → charged out-of-pocket (generated room revenue)
    # paid: false → covered by membership / free room
    @paid_reservations = reservations_scope.where(paid: true).distinct.count
    @member_reservations = reservations_scope.where(paid: false).distinct.count

    # Per-room usage covers ACTIVE rooms only — archived rooms would
    # otherwise haunt every weekly update at 0% forever. `utilization` is
    # booked time clipped to the business window over the window's total
    # hours; cancelled reservations don't count as usage.
    active_rooms = location.rooms.active.to_a
    room_scope = Reservation.where(room_id: active_rooms.map(&:id))
      .for_week(@week_start, @week_end).not_cancelled
    room_counts = room_scope.group(:room_id).count
    booked_minutes = business_window_minutes_by_room(room_scope)
    available_minutes = business_windows.sum { |win_start, win_end| (win_end - win_start) / 60.0 }

    @rooms = active_rooms.map do |room|
      utilization = available_minutes.zero? ? 0.0 : booked_minutes[room.id] / available_minutes

      {
        utilization: utilization.round(4),
        name: room.name,
        count: room_counts[room.id] || 0
      }
    end.sort_by { |room| -room[:utilization] }

    @paid_invoices = location.invoices.for_week(@week_start, @week_end).paid
    @unpaid_invoices = location.invoices.for_week(@week_start, @week_end).open
    @revenue = @paid_invoices.sum(:amount_due).to_f / 100.0

    @management_notes = location.feed_items.notes.for_week(@week_start, @week_end)

    @questions = @management_notes.questions

    @unanswered_questions = @questions.unanswered

    @admins = User.relevant_admins_of_location(location).admins

    @room_demand_misses = RoomDemandMiss.for_location(location).for_week(@week_start, @week_end).count
  end

  private

  # The week's business windows as [start, end] instants in the location's
  # zone. Derived from week_start/week_end so a mid-week invocation still
  # lines up with the calendar days it covers.
  def business_windows
    @business_windows ||= begin
      zone = ActiveSupport::TimeZone[location.time_zone] || Time.zone
      (@week_start.to_date..@week_end.to_date).filter_map do |day|
        next unless BUSINESS_WDAYS.cover?(day.wday)

        [
          zone.local(day.year, day.month, day.day, BUSINESS_DAY_START_HOUR),
          zone.local(day.year, day.month, day.day, BUSINESS_DAY_END_HOUR),
        ]
      end
    end
  end

  # Minutes of reservation time per room that fall INSIDE the business
  # windows. A 5pm-8pm booking contributes 60 minutes; a weekend booking
  # contributes 0. Overlap math compares UTC instants, so the raw plucked
  # timestamps don't need zone conversion.
  def business_window_minutes_by_room(reservation_scope)
    minutes = Hash.new(0.0)
    reservation_scope.pluck(:room_id, :datetime_in, :minutes).each do |room_id, starts_at, duration|
      ends_at = starts_at + duration.to_i.minutes
      business_windows.each do |win_start, win_end|
        overlap = [ends_at, win_end].min - [starts_at, win_start].max
        minutes[room_id] += overlap / 60.0 if overlap.positive?
      end
    end
    minutes
  end
end