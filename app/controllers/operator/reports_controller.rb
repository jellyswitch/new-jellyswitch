class Operator::ReportsController < Operator::BaseController
  before_action :background_image
  before_action :generate_report

  def index
  end

  def active_lease_members
  end

  def active_members
  end

  def active_leases
  end

  def last_30_day_passes
  end

  def total_members
  end

  def membership_breakdown
  end

  private

  def generate_report
    @report = Jellyswitch::Report.new(current_tenant)
  end
end