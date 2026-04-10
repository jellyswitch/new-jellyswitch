class Api::V1::Admin::TodaysActivityController < Api::V1::Admin::BaseController
  def index
    today = Date.current
    location = current_location

    # Today's reservations
    todays_reservations = Reservation.joins(:room)
                                     .where(rooms: { operator_id: current_tenant.id })
                                     .where(datetime_in: today.beginning_of_day..today.end_of_day)

    paid_bookings = todays_reservations.where(paid: true)
    member_bookings = todays_reservations.where(paid: [false, nil])

    # Today's day passes
    todays_day_passes = DayPass.where(operator: current_tenant, day: today)

    # Revenue total
    revenue_total = paid_bookings.sum { |r| r.room_price } +
                    todays_day_passes.joins(:day_pass_type).sum('day_pass_types.amount_in_cents')

    # New members (approved in last 7 days)
    new_members = current_tenant.users
                                .where(approved: true)
                                .where.not(role: 'admin')
                                .where(created_at: 7.days.ago..Time.current)
                                .order(created_at: :desc)

    # Visitor count
    visitor_count = paid_bookings.distinct.count(:user_id) +
                    todays_day_passes.distinct.count(:user_id) +
                    member_bookings.distinct.count(:user_id)

    render json: {
      visitor_count: visitor_count,
      revenue_total: revenue_total,
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
      new_members: new_members.includes(:subscriptions).map { |u|
        active_sub = u.subscriptions.find { |s| s.active? && !s.pending? }
        {
          user_name: u.name,
          plan_name: active_sub&.plan&.name,
          joined_at: u.created_at
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
