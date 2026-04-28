class Api::V1::Admin::EventsController < Api::V1::Admin::BaseController
  def index
    events = Event.where(location: current_location).order(:starts_at)

    case params[:scope]
    when 'upcoming'
      events = events.approved.future
    when 'past'
      events = events.approved.past
    when 'pending'
      events = events.pending_approval.order(created_at: :desc)
    end

    render json: events.map { |e| event_json(e) }
  end

  def create
    # Admin-created events are auto-approved.
    event = Event.new(event_params)
    event.location = current_location
    event.user = current_api_user
    event.approved_at ||= Time.current

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

  def approve
    event = Event.find(params[:id])
    event.update!(approved_at: Time.current, rejected_at: nil)
    # TODO: Notify the submitter via push if ios_token present.
    render json: event_json(event)
  end

  def reject
    event = Event.find(params[:id])
    event.update!(rejected_at: Time.current, approved_at: nil)
    render json: event_json(event)
  end

  private

  def event_params
    params.require(:event).permit(:title, :description, :starts_at, :ends_at, :location_string, :image)
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
      hosted_by: e.user&.name,
      submitted_via_app: e.submitted_via_app,
      approved: e.approved?,
      pending: e.pending_approval?,
      rejected: e.rejected?,
      image_url: (e.image.attached? ? url_for(e.image) : nil rescue nil),
    }
  end
end
