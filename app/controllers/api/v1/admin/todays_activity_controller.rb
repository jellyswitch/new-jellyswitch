class Api::V1::Admin::TodaysActivityController < Api::V1::Admin::BaseController
  def index
    today = Date.current

    # Today's reservations
    todays_reservations = Reservation.joins(:room)
                                     .where(rooms: { operator_id: current_tenant.id })
                                     .where(datetime_in: today.beginning_of_day..today.end_of_day)

    paid_bookings = todays_reservations.where(paid: true)
    member_bookings = todays_reservations.where(paid: [false, nil])

    # Today's day passes
    todays_day_passes = DayPass.where(operator: current_tenant, day: today)

    # Today's new subscriptions (catches converted day-passers: their User
    # record may be old, but the subscription started today).
    todays_new_subscriptions = Subscription
      .joins(:plan)
      .where(operator: current_tenant)
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
    new_members = current_tenant.users
                                .joins(:subscriptions)
                                .where(subscriptions: { active: true, pending: [false, nil] })
                                .where('subscriptions.created_at >= ?', 7.days.ago)
                                .where(approved: true)
                                .where.not(role: 'admin')
                                .distinct
                                .order('subscriptions.created_at DESC')

    # Visitor count
    visitor_count = paid_bookings.distinct.count(:user_id) +
                    todays_day_passes.distinct.count(:user_id) +
                    member_bookings.distinct.count(:user_id)

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
          user_name: r.user.name,
          room_name: r.room.name,
          time: r.datetime_in.strftime("%l:%M %p").strip,
          amount: r.room_price,
          first_timer: first_timer?(r.user, today)
        }
      },
      day_passes: todays_day_passes.includes(:user, :day_pass_type).map { |dp|
        {
          user_name: dp.user.name,
          type_name: dp.day_pass_type_name,
          cost: dp.day_pass_type&.amount_in_cents || 0,
          first_timer: first_timer?(dp.user, today)
        }
      },
      member_bookings: member_bookings.includes(:user, :room).map { |r|
        {
          user_name: r.user.name,
          room_name: r.room.name,
          time: r.datetime_in.strftime("%l:%M %p").strip
        }
      },
      new_members: new_members.includes(:subscriptions, :day_passes).map { |u|
        active_sub = u.subscriptions.find { |s| s.active? && !s.pending? }
        # Was this person a day-passer before becoming a subscriber? The
        # converted-day-passer story is worth surfacing in the UI — it's
        # the single biggest tell of an operator's day-pass funnel working.
        first_day_pass = u.day_passes.order(:created_at).first
        was_daypasser = first_day_pass.present? && active_sub.present? &&
                        first_day_pass.created_at < active_sub.created_at
        {
          user_name: u.name,
          plan_name: active_sub&.plan&.name,
          joined_at: active_sub&.created_at || u.created_at,
          was_daypasser: was_daypasser,
        }
      }
    }
  end

  private

  def first_timer?(user, today)
    !user.checkins.where("datetime_in < ?", today.beginning_of_day).exists? &&
      !user.reservations.unscoped.where(user: user, cancelled: false).where("datetime_in < ?", today.beginning_of_day).exists?
  end
end
