# typed: false
class Operator::EventsController < Operator::BaseController
  include EventHelper
  before_action :background_image

  def index
    find_events
  end

  def show
    find_event
  end

  def new
    @event = Event.new
  end

  def create
    result = Events::Create.call(
      location: current_location,
      user: current_user,
      event_params: event_params
    )

    if result.success?
      flash[:success] = "Event created."
      turbolinks_redirect(event_path(result.event), action: "replace")
    else
      flash[:error] = result.message
      @event = Event.new(event_params)
    end
  end
end