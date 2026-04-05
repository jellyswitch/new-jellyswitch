
class Operator::ReportsController < Operator::BaseController
  before_action :background_image
  before_action :generate_report, except: [:monetization]

  def index
    authorize :report, :index?
    @period = params[:period] || "12m"
    @period_days = case @period
                   when "30d" then 30
                   when "90d" then 90
                   when "12m" then 365
                   when "ytd" then (Date.today - Date.today.beginning_of_year).to_i
                   when "all" then 3650
                   else 365
                   end
    @location_events = LocationEvent.where(operator: current_tenant, location: current_location)
                                    .order(date: :desc).limit(10) if current_location
    @insights = current_location ? (@report.actionable_insights rescue []) : []

    if current_location
      @mrr_value = @report.mrr rescue 0
      @churn_value = @report.churn_rate(@period_days) rescue 0
      @churned_count = @report.churned_members_count(@period_days) rescue 0
      @growth_value = @report.net_member_growth(@period_days) rescue 0
      @new_count = @report.new_members_count(@period_days) rescue 0
      @util_value = @report.room_utilization(@period_days) rescue 0
      @visits_value = @report.avg_visits_per_member_per_month(@period_days) rescue 0
      @daily_visitors = @report.avg_daily_visitors(@period_days) rescue 0
    end
  end

  def create_location_event
    authorize :report, :index?
    LocationEvent.create!(
      operator: current_tenant,
      location: current_location,
      name: params[:location_event][:name],
      date: params[:location_event][:date]
    )
    flash[:notice] = "Event added."
    turbo_redirect(reports_path)
  end

  def delete_location_event
    authorize :report, :index?
    LocationEvent.find(params[:id]).destroy
    flash[:notice] = "Event removed."
    turbo_redirect(reports_path)
  end

  def member_csv
    authorize :report, :member_csv?
    MemberCsvExportJob.perform_later(current_tenant.id, current_location&.id, current_user.email)
    redirect_to reports_path, notice: "Your member CSV is being generated. It will be emailed to #{current_user.email} shortly."
  end

  def active_lease_members
    authorize :report, :active_lease_members?
  end

  def active_members
    authorize :report, :active_members?
  end

  def active_leases
    authorize :report, :active_leases?
  end

  def last_30_day_passes
    authorize :report, :last_30_day_passes?
  end

  def total_members
    authorize :report, :total_members?
  end

  def membership_breakdown
    authorize :report, :membership_breakdown?
  end

  def revenue
    authorize :report, :revenue?
  end

  def checkins
    authorize :report, :checkins?
  end

  def ltv
    authorize :report, :ltv?
    @ltv_1y = @report.ltv_for_timeframe(since: 1.year.ago)
    @ltv_2_5y = @report.ltv_for_timeframe(since: 30.months.ago)
    @ltv_all = @report.ltv_for_timeframe(since: nil)
  end

  def room_demand
    authorize :report, :revenue?
    @demand_misses = RoomDemandMiss.for_location(current_location)
    @total_misses_30d = @demand_misses.last_30_days.count
    @heatmap_data = @demand_misses.last_30_days.group(:day_of_week, :hour_of_day).count
    @peak_times = RoomDemandMiss.peak_times(current_location)
    @estimated_missed_revenue = RoomDemandMiss.estimated_missed_revenue(current_location)
    @misses_by_week = @demand_misses.where("missed_at >= ?", 12.weeks.ago)
                                     .group_by_week(:missed_at)
                                     .count
  end

  def monetization
    @location = Location.find(params[:location_id])
    authorize :report, :monetization?
    @report = Jellyswitch::MonetizationReport.new(@location)
  end

  private

  def generate_report
    @report = Jellyswitch::Report.new(current_tenant, current_location)
  end
end