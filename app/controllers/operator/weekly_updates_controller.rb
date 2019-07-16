class Operator::WeeklyUpdatesController < Operator::BaseController
  before_action :background_image
  include ActionView::Helpers::NumberHelper
  
  def index
    @week_start = Time.current.beginning_of_week
    @week_end = Time.current.end_of_week

    @report = Jellyswitch::WeeklyReport.new(current_tenant, @week_start, @week_end)
  end
end