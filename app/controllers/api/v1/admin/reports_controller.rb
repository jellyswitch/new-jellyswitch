class Api::V1::Admin::ReportsController < Api::V1::Admin::BaseController
  def index
    period_start = period_start_date

    render json: {
      current_mrr: current_mrr,
      avg_monthly_revenue: avg_monthly_revenue(period_start),
      active_members: current_tenant.users.where(approved: true, archived: false).count,
      revenue: Invoice.where(operator: current_tenant)
        .where("date >= ?", period_start).sum(:amount_paid),
      churn_count: Subscription.joins(:plan)
        .where(plans: { operator_id: current_tenant.id })
        .where(active: false)
        .where("subscriptions.updated_at >= ?", period_start).count,
      room_utilization: calculate_room_utilization(period_start),
      daily_visitors: Checkin.where(location: current_location)
        .where(datetime_in: Date.current.all_day).count,
      period: params[:period] || '30',
    }
  end

  def revenue
    period = (params[:period] || '12').to_i
    months = (0..[period - 1, 23].min).map { |i| i.months.ago.beginning_of_month }

    data = months.map { |month_start|
      month_end = month_start.end_of_month
      amount = Invoice.where(operator: current_tenant)
        .where(date: month_start..month_end).sum(:amount_paid)
      {
        month: month_start.strftime("%Y-%m"),
        label: month_start.strftime("%b %Y"),
        amount: amount,
      }
    }

    render json: { months: data.reverse }
  end

  def room_demand
    period_start = period_start_date

    rooms = Room.where(operator: current_tenant)
    data = rooms.map { |room|
      reservations = room.reservations.where("datetime_in >= ?", period_start).where(cancelled: false)
      total_hours = reservations.sum(:minutes) / 60.0
      days_in_period = [(Date.current - period_start.to_date).to_i, 1].max
      work_hours = days_in_period * 8.0
      utilization = work_hours > 0 ? ((total_hours / work_hours) * 100).round(1) : 0

      {
        name: room.name,
        bookings: reservations.count,
        revenue: reservations.sum(:hours) * room.hourly_rate_in_cents / 100,
        utilization: utilization,
      }
    }

    render json: { rooms: data }
  end

  def members
    plans = Plan.where(operator: current_tenant)

    data = plans.map { |plan|
      {
        plan_name: plan.name,
        count: plan.subscriptions.where(active: true).count,
      }
    }

    render json: data
  end

  def checkins
    data = (0..29).map { |i|
      date = i.days.ago.to_date
      count = Checkin.where(location: current_location)
        .where(datetime_in: date.all_day).count
      { date: date.iso8601, count: count }
    }

    render json: data.reverse
  end

  def ltv
    active_count = current_tenant.users.where(approved: true, archived: false).count
    total_paid = Invoice.where(operator: current_tenant).sum(:amount_paid)

    avg_ltv = active_count > 0 ? (total_paid.to_f / active_count).round : 0

    render json: { average_ltv: avg_ltv, active_members: active_count }
  end

  def member_csv
    MemberCsvExportJob.perform_later(current_tenant.id, current_api_user.id)
    render json: { success: true, message: "CSV export queued. You will receive it by email." }
  end

  private

  def period_start_date
    case params[:period]
    when '7' then 7.days.ago
    when '30' then 30.days.ago
    when '90' then 90.days.ago
    when '12' then 12.months.ago
    when 'ytd' then Time.current.beginning_of_year
    when 'all' then Time.at(0)
    else 30.days.ago
    end
  end

  def current_mrr
    Subscription.joins(:plan)
      .where(plans: { operator_id: current_tenant.id })
      .where(active: true)
      .sum("plans.amount_in_cents")
  end

  def avg_monthly_revenue(period_start)
    months_in_period = [(Date.current.year * 12 + Date.current.month) - (period_start.to_date.year * 12 + period_start.to_date.month), 1].max
    total_revenue = Invoice.where(operator: current_tenant)
      .where("date >= ?", period_start)
      .sum(:amount_paid)
    (total_revenue.to_f / months_in_period).round
  end

  def calculate_room_utilization(period_start = Time.current.beginning_of_day)
    rooms_count = Room.where(operator: current_tenant).count
    return 0 if rooms_count == 0

    reservations = Reservation.joins(:room)
      .where(rooms: { operator_id: current_tenant.id })
      .where("datetime_in >= ?", period_start)
      .where(cancelled: false).count

    days_in_period = [(Date.current - period_start.to_date).to_i, 1].max
    slots_available = rooms_count * days_in_period
    ((reservations.to_f / slots_available) * 100).round(1)
  end
end
