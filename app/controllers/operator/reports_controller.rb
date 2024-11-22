
class Operator::ReportsController < Operator::BaseController
  before_action :background_image
  before_action :generate_report, except: [:monetization]

  def index
    authorize :report, :index?
  end

  def member_csv
    authorize :report, :member_csv?
    send_data @report.member_csv, filename: "Jellyswitch-Member-Data-#{short_date(Time.current)}.csv"
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