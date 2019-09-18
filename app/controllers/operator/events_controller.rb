# typed: false
class Operator::EventsController < Operator::BaseController
  include EventHelper
  before_action :background_image

  def index
    find_events
    authorize Event
  end

  def past
    find_past_events
    authorize Event
  end

  def show
    find_event
    authorize @event
  end

  def new
    @event = Event.new
    authorize @event
  end

  def create
    authorize Event.new
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

  def edit
    find_event
    authorize @event
  end

  def update
    find_event
    authorize @event

    result = Events::Update.call(
      event: @event,
      location: current_location,
      user: current_user,
      event_params: event_params
    )

    if result.success?
      flash[:success] = "Event updated."
      turbolinks_redirect(event_path(result.event), action: "replace")
    else
      flash[:error] = result.message
      render :edit
    end
  end
end