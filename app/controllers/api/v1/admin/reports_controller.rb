class Api::V1::Admin::ReportsController < Api::V1::Admin::BaseController
  # Mirrors the prod web Operator::ReportsController#index analytics dashboard:
  # all the KPIs, multi-timeframe trends, and actionable insights — surfaced
  # as JSON so the mobile admin reports screen can render the same view.
  def index
    period_days = period_days_for(params[:period])
    period_start, period_end = period_window_for(params[:period])
    report = Jellyswitch::Report.new(current_tenant, current_location)

    mrr_value = safe(0) { report.mrr }
    avg_mrr_value = safe(0) { report.avg_mrr(period_days) }
    churn_rate_value = safe(0) { report.churn_rate(period_days) }
    churn_count_value = safe(0) { report.churned_members_count(period_days) }
    growth_value = safe(0) { report.net_member_growth(period_days) }
    new_count_value = safe(0) { report.new_members_count(period_days) }
    util_value = safe(0) { report.room_utilization(period_days) }
    visits_value = safe(0) { report.avg_visits_per_member_per_month(period_days) }
    daily_visitors_value = safe(0) { report.avg_daily_visitors(period_days) }
    rev_per_member = safe(0) { report.revenue_per_member }
    avg_tenure = safe(0) { report.average_member_tenure }
    dp_conv = safe(0) { report.day_pass_conversion_rate }

    # Revenue mirrors the web dashboard's revenue_by_month: paid invoices in
    # the window + lease_supplement_for_month for out-of-band lease checks.
    # `current_month` / `last_month` keep an explicit date-range so those
    # period chips return invoices dated within that month.
    revenue_total = safe(0) do
      if %w[current_month last_month].include?(params[:period])
        invoice_rev = Invoice.where(operator: current_tenant)
          .where(date: period_start..period_end).sum(:amount_paid)
        invoice_rev # already cents
      else
        (report.revenue_for_period(period_days) * 100).to_i # convert dollars → cents
      end
    end

    render json: {
      period: params[:period] || '30',
      period_days: period_days,
      # Primary KPIs
      current_mrr: (mrr_value * 100).to_i, # cents — mobile divides by 100
      avg_mrr: (avg_mrr_value * 100).to_i, # cents — period-averaged MRR
      revenue: revenue_total, # cents
      active_members: safe(0) { report.active_member_count },
      churn_rate: churn_rate_value,
      churn_count: churn_count_value,
      net_growth: growth_value,
      new_members: new_count_value,
      room_utilization: util_value,
      avg_visits_per_member: visits_value,
      daily_visitors: daily_visitors_value,
      revenue_per_member: (rev_per_member * 100).to_i, # cents
      avg_tenure_months: avg_tenure,
      day_pass_count: safe(0) { report.day_pass_count(period_days) },
      checkin_count: safe(0) { report.checkin_count(period_days) },
      day_pass_conversion_rate: dp_conv,

      # Multi-timeframe trends — % change vs 30/90/365 days ago, per metric.
      # Mirrors the prod web KPI cards which render "30d: +5%  90d: +12%".
      trends: {
        mrr: safe({}) { report.trends_for(:mrr, mrr_value) },
        churn: safe({}) { report.trends_for(:churn, churn_rate_value) },
        room_utilization: safe({}) { report.trends_for(:room_utilization, util_value) },
        visits_per_member: safe({}) { report.trends_for(:visits_per_member, visits_value) },
        active_members: safe({}) { report.trends_for(:active_members, report.active_member_count) },
      },

      # Actionable insights — same source the web dashboard renders.
      # Each: { text, action, urgency, screen, route } — `screen` and
      # `route` are mobile-friendly mappings of the web `path` symbol.
      insights: safe([]) { report.actionable_insights }.map { |i| insight_to_json(i) },
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
    period_start, period_end = period_window_for(params[:period])
    days_in_period = [(period_end - period_start).to_i + 1, 1].max

    rooms = Room.where(operator: current_tenant)
    data = rooms.map { |room|
      reservations = room.reservations
        .where(datetime_in: period_start.beginning_of_day..period_end.end_of_day)
        .where(cancelled: false)
      total_hours = reservations.sum(:minutes) / 60.0
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

    breakdown = plans.map { |plan|
      {
        plan_name: plan.name,
        count: plan.subscriptions.where(active: true).count,
      }
    }

    render json: { breakdown: breakdown }
  end

  # All members who haven't visited in 30+ days. Excludes
  # marketing-suppressed users and dismissed-in-the-last-30-days.
  def inactive_members
    report = Jellyswitch::Report.new(current_tenant, current_location)
    users = report.inactive_members
      .where(marketing_suppressed: false)
      .where("inactive_dismissed_at IS NULL OR inactive_dismissed_at < ?", 30.days.ago)

    render json: {
      members: users.map { |u| inactive_member_json(u) },
      suppressed_count: User.for_space(current_tenant).where(marketing_suppressed: true).count,
    }
  end

  # All members suppressed from marketing.
  def suppressed_members
    users = User.for_space(current_tenant).where(marketing_suppressed: true).order(:name)
    render json: {
      members: users.map { |u| {
        id: u.id,
        name: u.name,
        email: u.email,
        marketing_suppressed_reason: u.marketing_suppressed_reason,
      } },
    }
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

  def safe(default)
    yield
  rescue => e
    Rails.logger.warn("ReportsController metric error: #{e.class}: #{e.message}")
    default
  end

  def period_days_for(period)
    case period
    when 'current_month' then (Date.current - Date.current.beginning_of_month).to_i + 1
    when 'last_month'
      last = Date.current.prev_month
      (last.end_of_month - last.beginning_of_month).to_i + 1
    when '7' then 7
    when '30' then 30
    when '90' then 90
    when '12', '12m' then 365
    when 'ytd' then [(Date.current - Date.current.beginning_of_year).to_i, 1].max
    when 'all' then 3650
    else 30
    end
  end

  # Returns [start_date, end_date] for the requested period. Used by
  # date-range queries (revenue) that need an explicit window — vs the
  # period_days count Report methods consume.
  def period_window_for(period)
    today = Date.current
    case period
    when 'current_month'
      [today.beginning_of_month, today]
    when 'last_month'
      last = today.prev_month
      [last.beginning_of_month, last.end_of_month]
    when 'ytd'
      [today.beginning_of_year, today]
    when 'all'
      [Date.new(2000, 1, 1), today]
    else
      [period_days_for(period).days.ago.to_date, today]
    end
  end

  # Web uses Rails route helpers (:inactive_members_reports_path etc.). For
  # mobile we map those symbols to React Navigation screen names + params
  # so the InsightCard "View ..." button can deep-link.
  # Maps the web path symbol Jellyswitch::Report uses to the mobile
  # navigator address. `tab` is set when the screen lives in a different
  # bottom-tab stack than AdminReports (which is in MoreTab), so the
  # InsightCard handler can do cross-tab navigation properly.
  WEB_TO_MOBILE_ROUTE = {
    inactive_members_reports_path: { screen: "AdminInactiveMembers" },
    total_members_reports_path: { tab: "MembersTab", screen: "Members" },
    room_demand_reports_path: { screen: "AdminReports" }, # no dedicated mobile screen
    active_leases_reports_path: { screen: "AdminOffices" },
    new_campaign_path: { screen: "AdminCampaigns" },
    rooms_path: { tab: "RoomsTab", screen: "AdminRooms" },
  }.freeze

  def insight_to_json(insight)
    mapped = WEB_TO_MOBILE_ROUTE[insight[:path]] || {}
    {
      text: insight[:text],
      action: insight[:action],
      urgency: insight[:urgency].to_s,
      tab: mapped[:tab],
      screen: mapped[:screen],
      params: mapped[:params],
    }
  end

  def inactive_member_json(user)
    last_door = DoorPunch.where(user: user).order(created_at: :desc).limit(1).pick(:created_at)
    last_res = Reservation.where(user: user).order(created_at: :desc).limit(1).pick(:created_at)
    last_visit = [last_door, last_res].compact.max
    {
      id: user.id,
      name: user.name,
      email: user.email,
      member_since: user.created_at.iso8601,
      last_visit: last_visit&.iso8601,
      days_since_visit: last_visit ? ((Time.current - last_visit) / 1.day).floor : nil,
      inactive_dismissed_at: user.inactive_dismissed_at&.iso8601,
      marketing_suppressed: user.marketing_suppressed,
    }
  end

end
