class Operator::WeeklyUpdatesController < Operator::BaseController
  before_action :background_image
  include ActionView::Helpers::NumberHelper

  def index
    find_weekly_updates
    authorize @weekly_updates
  end

  def show
    find_weekly_update
    authorize @weekly_update
  end

  def create
    @week_start = Time.current.beginning_of_week
    @week_end = Time.current.end_of_week
    authorize WeeklyUpdate

    result = WeeklyUpdates::Create.call(operator: current_tenant, location: current_location, week_start: @week_start, week_end: @week_end)

    if result.success?
      turbo_redirect(weekly_update_path(result.weekly_update), action: "replace")
    else
      flash[:error] = result.message
      turbo_redirect(weekly_updates_path, action: "replace")
    end
  end

  private

  def find_weekly_updates
    @pagy, @weekly_updates = pagy(current_location.weekly_updates.order('week_start DESC'))
  end

  def find_weekly_update(key=:id)
    @weekly_update = current_location.weekly_updates.find(params[key])
  end
end