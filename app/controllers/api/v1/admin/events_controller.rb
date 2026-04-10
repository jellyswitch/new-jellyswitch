class Api::V1::Admin::EventsController < Api::V1::Admin::BaseController
  def index
    events = Event.where(location: current_location).order(:starts_at)

    if params[:scope] == 'upcoming'
      events = events.future
    elsif params[:scope] == 'past'
      events = events.past
    end

    render json: events.map { |e| event_json(e) }
  end

  def create
    event = Event.new(event_params)
    event.location = current_location
    event.user = current_api_user

    if event.save
      render json: event_json(event), status: :created
    else
      render_error(event.errors.full_messages.join(', '))
    end
  end

  def update
    event = Event.find(params[:id])

    if event.update(event_params)
      render json: event_json(event)
    else
      render_error(event.errors.full_messages.join(', '))
    end
  end

  def destroy
    event = Event.find(params[:id])
    event.destroy
    render json: { success: true }
  end

  private

  def event_params
    params.require(:event).permit(:title, :description, :starts_at, :ends_at, :location_string)
  end

  def event_json(e)
    {
      id: e.id,
      title: e.title,
      description: e.description,
      starts_at: e.starts_at,
      ends_at: e.ends_at,
      location_string: e.location_string,
      rsvp_count: e.rsvps.count,
    }
  end
end
