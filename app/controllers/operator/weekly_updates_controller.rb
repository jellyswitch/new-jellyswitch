class Operator::WeeklyUpdatesController < Operator::BaseController
  before_action :background_image
  include ActionView::Helpers::NumberHelper
  
  def index
    @week_start = Time.current.beginning_of_week
    @week_end = Time.current.end_of_week

    @report = Jellyswitch::Report.new(current_tenant)

    @day_passes = current_tenant.day_passes.for_week(@week_start, @week_end).count
    @checkins = current_tenant.checkins.for_week(@week_start, @week_end).count

    @new_active_members = current_tenant.plans.individual.nonzero.map do |plan|
      plan.subscriptions.active.for_week(@week_start, @week_end).map(&:subscribable)
    end.flatten.uniq.count
    @new_free_members = current_tenant.plans.individual.free.map do |plan|
      plan.subscriptions.active.for_week(@week_start, @week_end).map(&:subscribable)
    end.flatten.uniq.count

    @reservations = current_tenant.rooms.map do |room|
      room.reservations.for_week(@week_start, @week_end)
    end.flatten.uniq.count

    @rooms = current_tenant.rooms.map do |room|
      count = room.reservations.for_week(@week_start, @week_end).count
      percent = @reservations == 0 ? 0 : count.to_f / @reservations.to_f
      name = room.name

      "#{number_to_percentage(room[:percent].to_f, precision: 0)} of which were in #{room[:name]}"
    end
  end
end