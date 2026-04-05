class Api::V1::EventsController < Api::V1::BaseController
  def index
    location = current_location
    events = Event.where(location: location).future.order(:starts_at).limit(20)
    user_rsvp_ids = current_api_user.rsvps.pluck(:event_id)

    render json: events.map { |e| {
      id: e.id,
      title: e.title,
      description: e.description,
      date: e.starts_at.strftime("%B %e, %Y"),
      time: e.starts_at.strftime("%l:%M %p").strip,
      location: e.location_string,
      rsvped: user_rsvp_ids.include?(e.id),
      rsvp_count: e.rsvps.count,
    }}
  end

  def rsvp
    event = Event.find(params[:id])
    existing = current_api_user.rsvps.find_by(event: event)

    if existing
      existing.destroy
      render json: { rsvped: false }
    else
      current_api_user.rsvps.create!(event: event)
      render json: { rsvped: true }
    end
  end
end
