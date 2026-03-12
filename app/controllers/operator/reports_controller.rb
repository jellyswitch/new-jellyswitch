
class Operator::ReportsController < Operator::BaseController
  before_action :background_image
  before_action :generate_report, except: [:monetization]

  def index
    authorize :report, :index?
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