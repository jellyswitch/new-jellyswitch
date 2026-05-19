class Api::V1::Admin::TodaysActivityController < Api::V1::Admin::BaseController
  def index
    today = Date.current
    location = current_location
    # Without a current_location we cannot scope safely; return an empty
    # day rather than risk surfacing another location's members.
    return render(json: empty_payload) unless location

    # Today's reservations — scoped to rooms at this location so a sister
    # location's bookings never leak in.
    todays_reservations = Reservation.joins(:room)
                                     .where(rooms: { location_id: location.id })
                                     .where(datetime_in: today.beginning_of_day..today.end_of_day)

    paid_bookings = todays_reservations.where(paid: true)
    member_bookings = todays_reservations.where(paid: [false, nil])

    # Today's day passes — scoped to this location, not the operator.
    todays_day_passes = DayPass.where(location: location, day: today)

    # Today's new subscriptions (catches converted day-passers: their User
    # record may be old, but the subscription started today). Scoped to
    # plans tied to this location.
    todays_new_subscriptions = Subscription
      .joins(:plan)
      .where(plans: { operator_id: current_tenant.id, location_id: location.id })
      .where(active: true, pending: [false, nil])
      .where(created_at: today.beginning_of_day..today.end_of_day)

    # Revenue total — all three pillars in cents.
    revenue_cents = paid_bookings.sum { |r| r.room_price } +
                    todays_day_passes.joins(:day_pass_type).sum('day_pass_types.amount_in_cents') +
                    todays_new_subscriptions.sum('plans.amount_in_cents')

    # New members — anyone whose ACTIVE subscription started in the last
    # 7 days. Previously filtered on `users.created_at`, which silently
    # excluded converted day-passers (their User row dates from their
    # first day-pass purchase, weeks or months earlier).
    #
    # Postgres rejects `DISTINCT ... ORDER BY subscriptions.created_at`
    # unless the order column is in the SELECT list, so we first
    # collect each candidate user's most-recent qualifying subscription
    # start, then load + sort in Ruby. Bounded list (max ~dozen rows),
    # so the in-memory sort is fine.
    sub_starts = Subscription
      .joins(:plan)
      .where(plans: { operator_id: current_tenant.id, location_id: location.id })
      .where(active: true, pending: [false, nil])
      .where(subscribable_type: 'User')
      .where('subscriptions.created_at >= ?', 7.days.ago)
      .group(:subscribable_id)
      .maximum('subscriptions.created_at')

    new_members = current_tenant.users
                                .where(id: sub_starts.keys, approved: true)
                                .where.not(role: 'admin')
                                .to_a
                                .sort_by { |u| sub_starts[u.id] }
                                .reverse

    # Walk-ins — members who actually arrived today (door punch or
    # checkin), regardless of whether they had a booking. Union of both
    # sources, deduped by user_id. The earliest event per user is
    # surfaced as "arrived at" in the UI. Scoped to this location only.
    today_start = today.beginning_of_day
    location_door_ids = location.doors.pluck(:id)
    door_first = DoorPunch.where(door_id: location_door_ids)
      .where("created_at >= ?", today_start)
      .group(:user_id).minimum(:created_at)
    checkin_first = Checkin.where(location_id: location.id)
      .where("datetime_in >= ?", today_start)
      .group(:user_id).minimum(:datetime_in)
    arrived_at_by_user = door_first.merge(checkin_first) { |_, a, b| [a, b].min }

    # Visitor count — distinct across bookings + walk-ins
    booking_user_ids = (paid_bookings.distinct.pluck(:user_id) +
                        todays_day_passes.distinct.pluck(:user_id) +
                        member_bookings.distinct.pluck(:user_id)).uniq.compact
    walk_in_user_ids = arrived_at_by_user.keys.compact
    visitor_count = (booking_user_ids + walk_in_user_ids).uniq.count

    # Walk-ins-only list — members here today not already shown under bookings.
    walk_in_only_ids = walk_in_user_ids - booking_user_ids
    walk_in_users = User.where(id: walk_in_only_ids).order(:name).to_a

    render json: {
      visitor_count: visitor_count,
      # Renamed from `revenue_total` so it matches the dashboard endpoint
      # and the mobile TodayScreen which reads `data.revenue`. Kept the
      # old key as an alias for one release in case any other client is
      # consuming it.
      revenue: revenue_cents,
      revenue_total: revenue_cents,
      paid_bookings: paid_bookings.includes(:user, :room).map { |r|
        {
          user_id: r.user_id,
          user_name: r.user.name,
          room_name: r.room.name,
          time: r.datetime_in.strftime("%l:%M %p").strip,
          amount: r.room_price,
          first_timer: first_timer?(r.user, today)
        }
      },
      day_passes: todays_day_passes.includes(:user, :day_pass_type).map { |dp|
        {
          user_id: dp.user_id,
          user_name: dp.user.name,
          type_name: dp.day_pass_type_name,
          cost: dp.day_pass_type&.amount_in_cents || 0,
          first_timer: first_timer?(dp.user, today)
        }
      },
      member_bookings: member_bookings.includes(:user, :room).map { |r|
        {
          user_id: r.user_id,
          user_name: r.user.name,
          room_name: r.room.name,
          time: r.datetime_in.strftime("%l:%M %p").strip
        }
      },
      # `new_members` is now a plain Array after the in-Ruby sort above,
      # so `.includes` doesn't apply. ActiveRecord still caches the
      # associations lazily; the bounded result size (a few per week)
      # makes the N+1 negligible here.
      walk_in_members: walk_in_users.map { |u|
        arrived = arrived_at_by_user[u.id]
        {
          user_id: u.id,
          user_name: u.name,
          arrived_at: arrived&.iso8601,
          arrived_time: arrived ? arrived.in_time_zone(Time.zone).strftime("%l:%M %p").strip : nil,
        }
      },
      new_members: new_members.map { |u|
        active_sub = u.subscriptions.find { |s| s.active? && !s.pending? }
        # Was this person a day-passer before becoming a subscriber? The
        # converted-day-passer story is worth surfacing in the UI — it's
        # the single biggest tell of an operator's day-pass funnel working.
        first_day_pass = u.day_passes.order(:created_at).first
        was_daypasser = first_day_pass.present? && active_sub.present? &&
                        first_day_pass.created_at < active_sub.created_at
        {
          user_id: u.id,
          user_name: u.name,
          plan_name: active_sub&.plan&.name,
          # Normalized monthly MRR contribution of this member's plan, in
          # cents. Both surfaces render this as "$X / mo" alongside the
          # plan name so the operator sees what each new member adds.
          monthly_amount: active_sub&.plan ? normalize_plan_to_monthly_cents(active_sub.plan) : 0,
          joined_at: active_sub&.created_at || u.created_at,
          was_daypasser: was_daypasser,
        }
      }
    }
  end

  private

  def empty_payload
    {
      visitor_count: 0,
      revenue: 0,
      revenue_total: 0,
      paid_bookings: [],
      day_passes: [],
      member_bookings: [],
      walk_in_members: [],
      new_members: [],
    }
  end

  def first_timer?(user, today)
    !user.checkins.where("datetime_in < ?", today.beginning_of_day).exists? &&
      !user.reservations.unscoped.where(user: user, cancelled: false).where("datetime_in < ?", today.beginning_of_day).exists?
  end

  # Mirrors Jellyswitch::Report#normalize_to_monthly but returns cents
  # (the rest of this controller's amounts are in cents).
  def normalize_plan_to_monthly_cents(plan)
    amount = plan.amount_in_cents.to_i
    case plan.interval
    when "monthly" then amount
    when "quarterly" then (amount / 3.0).round
    when "biannually" then (amount / 6.0).round
    when "annually" then (amount / 12.0).round
    else amount
    end
  end
end
