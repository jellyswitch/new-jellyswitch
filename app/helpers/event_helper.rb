module EventHelper
  def find_events
    @events = current_location.events.future.order("starts_at ASC").group_by_day(&:starts_at)
  end

  def find_past_events
    @events = current_location.events.past.order("starts_at ASC").group_by_day(reverse: true) { |i| i.starts_at }
  end

  def find_upcoming_events
    @events = current_location.events.future.limit(1).order("starts_at ASC").group_by_day(&:starts_at)
  end

  def find_todays_events
    @events = current_location.events.today.order("starts_at ASC")
  end

  def find_event
    @event = current_location.events.find(params[:id])
  end

  def event_params
    p = params.require(:event).permit(:title, :description, :starts_at, :ends_at, :image, :location_string)
  end
end