class Operator::TodaysActivityController < Operator::BaseController
  def index
    authorize :report, :index?
    background_image

    # Today's day passes (scheduled for today)
    @day_passes = current_location.day_passes.today.includes(:user, :day_pass_type)

    # Today's reservations grouped by paid/free
    @all_reservations = Reservation.where(room: current_location.rooms)
      .today
      .includes(:user, :room)
      .order(:datetime_in)
    @paid_reservations = @all_reservations.select(&:paid?)
    @free_reservations = @all_reservations.reject(&:paid?)

    # New members — anyone whose ACTIVE subscription started in the last
    # 7 days. Scoped to plans tied to the current location so a sister
    # location's signups never appear here. Filtering on users.created_at
    # (the previous behavior) silently excluded converted day-passers whose
    # User row dates from their first day-pass purchase weeks or months
    # earlier; their *subscription* started recently.
    sub_starts = Subscription
      .joins(:plan)
      .where(plans: { operator_id: current_tenant.id, location_id: current_location.id })
      .where(active: true, pending: [false, nil])
      .where(subscribable_type: 'User')
      .where('subscriptions.created_at >= ?', 7.days.ago)
      .group(:subscribable_id)
      .maximum('subscriptions.created_at')
    @new_members = User
      .where(id: sub_starts.keys)
      .approved.visible
      .where.not(role: 'admin')
      .includes(:subscriptions)
      .to_a
      .sort_by { |u| sub_starts[u.id] || Time.zone.now }
      .reverse

    # Walk-ins — members who actually showed up today (door punch or
    # checkin), regardless of whether they had a booking. Union of both
    # sources, dedup by user_id. The earliest event time per user gives
    # an "arrived at" stamp for the UI.
    today_start = Date.current.beginning_of_day
    door_first = DoorPunch.where(door: current_location.doors)
      .where("created_at >= ?", today_start)
      .group(:user_id).minimum(:created_at)
    checkin_first = Checkin.where(location: current_location)
      .where("datetime_in >= ?", today_start)
      .group(:user_id).minimum(:datetime_in)
    @arrived_at_by_user = door_first.merge(checkin_first) { |_, a, b| [a, b].min }

    # Total visitors expected — distinct across bookings + walk-ins
    day_pass_user_ids = @day_passes.map(&:user_id)
    reservation_user_ids = @all_reservations.map(&:user_id)
    walk_in_user_ids = @arrived_at_by_user.keys.compact
    @total_visitors = (day_pass_user_ids + reservation_user_ids + walk_in_user_ids).uniq.count

    # Walk-ins shown in their own section: members here today who AREN'T
    # already listed under day passes / reservations.
    already_listed = (day_pass_user_ids + reservation_user_ids).uniq
    walk_in_only_ids = walk_in_user_ids - already_listed
    @walk_in_members = User.where(id: walk_in_only_ids).order(:name).to_a

    # Collect all user IDs for first-timer check (batch query)
    all_user_ids = (day_pass_user_ids + reservation_user_ids).uniq
    @first_timer_ids = detect_first_timers(all_user_ids)

    # Revenue totals — match the mobile API: paid rooms + day passes +
    # today's new subscription plan amounts (catches converted day-passers
    # whose User row is older than today but whose sub started today).
    @paid_reservation_revenue = @paid_reservations.sum { |r| r.room.hourly_rate_in_cents * (r.minutes / 60.0) / 100.0 }
    @day_pass_revenue = @day_passes.sum { |dp| dp.day_pass_type&.amount_in_cents.to_i / 100.0 }
    @new_subscription_revenue = Subscription.joins(:plan)
      .where(plans: { operator_id: current_tenant.id, location_id: current_location.id })
      .where(active: true, pending: [false, nil])
      .where(created_at: Date.current.beginning_of_day..Date.current.end_of_day)
      .sum('plans.amount_in_cents').to_f / 100.0
  end

  private

  def detect_first_timers(user_ids)
    return Set.new if user_ids.empty?

    # Users who have NO day passes before today and NO reservations before today
    users_with_prior_passes = DayPass.where(user_id: user_ids)
      .where("day < ?", Date.current)
      .pluck(:user_id).uniq

    users_with_prior_reservations = Reservation.where(user_id: user_ids)
      .where("datetime_in < ?", Time.current.beginning_of_day)
      .pluck(:user_id).uniq

    prior_visitors = (users_with_prior_passes + users_with_prior_reservations).uniq
    Set.new(user_ids - prior_visitors)
  end
end
