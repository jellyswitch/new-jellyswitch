class Jellyswitch::WeeklyReport
  include ActionView::Helpers::NumberHelper
  attr_reader :week_start, :week_end, :report, :operator, :location, :day_passes, :checkins, :new_active_members, :new_free_members, :rooms, :paid_invoices, :unpaid_invoices, :revenue, :reservations, :management_notes, :questions, :unanswered_questions, :admins

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

    @reservations = Reservation.where(room: location.rooms).for_week(@week_start, @week_end).distinct.count

    room_counts = Reservation.where(room: location.rooms)
      .for_week(@week_start, @week_end)
      .group(:room_id).count
    @rooms = location.rooms.map do |room|
      count = room_counts[room.id] || 0
      percent = @reservations == 0 ? 0 : count.to_f / @reservations.to_f

      {
        percent: percent.to_f,
        name: room.name,
        count: count
      }
    end

    @paid_invoices = location.invoices.for_week(@week_start, @week_end).paid
    @unpaid_invoices = location.invoices.for_week(@week_start, @week_end).open
    @revenue = @paid_invoices.sum(:amount_due).to_f / 100.0

    @management_notes = location.feed_items.notes.for_week(@week_start, @week_end)

    @questions = @management_notes.questions

    @unanswered_questions = @questions.unanswered

    @admins = User.relevant_admins_of_location(location).admins
  end
end