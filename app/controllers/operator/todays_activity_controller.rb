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

    # New members (approved in last 7 days with active subscription)
    @new_members = User.originally_at_location(current_location)
      .approved.visible
      .where("users.created_at > ?", 7.days.ago)
      .includes(:subscriptions)
      .select { |u| u.subscriptions.active.any? }

    # Total visitors expected
    day_pass_user_ids = @day_passes.map(&:user_id)
    reservation_user_ids = @all_reservations.map(&:user_id)
    @total_visitors = (day_pass_user_ids + reservation_user_ids).uniq.count

    # Collect all user IDs for first-timer check (batch query)
    all_user_ids = (day_pass_user_ids + reservation_user_ids).uniq
    @first_timer_ids = detect_first_timers(all_user_ids)

    # Revenue totals
    @paid_reservation_revenue = @paid_reservations.sum { |r| r.room.hourly_rate_in_cents * (r.minutes / 60.0) / 100.0 }
    @day_pass_revenue = @day_passes.sum { |dp| dp.day_pass_type&.amount_in_cents.to_i / 100.0 }
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
