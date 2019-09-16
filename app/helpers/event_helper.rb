module EventHelper
  def find_events
    @events = current_location.events.order("starts_at ASC").all
  end

  def find_event
    @event = current_location.events.find(params[:id])
  end

  def event_params
    p = params.require(:event).permit(:title, :description, :starts_at, :ends_at, :image)
  end
end