class Api::V1::EventsController < Api::V1::BaseController
  # Member-facing events: only approved events are visible.
  def index
    location = current_location
    events = Event.where(location: location).approved.future.order(:starts_at).limit(20)
    user_rsvp_ids = current_api_user.rsvps.pluck(:event_id)

    render json: events.map { |e| event_card_json(e, user_rsvp_ids) }
  end

  def show
    event = Event.find(params[:id])
    return render_error('Event not found', status: :not_found) unless event.approved? || event.user_id == current_api_user.id

    render json: {
      id: event.id,
      title: event.title,
      description: event.description,
      date: event.starts_at.strftime("%B %e, %Y"),
      time: event.starts_at.strftime("%l:%M %p").strip,
      end_time: event.ends_at&.strftime("%l:%M %p")&.strip,
      location: event.location_string,
      image_url: (event.image.attached? ? url_for(event.image) : nil rescue nil),
      hosted_by: event.user&.name,
      rsvped: current_api_user.rsvps.exists?(event: event),
      rsvp_count: event.rsvps.count,
      approved: event.approved?,
      pending_approval: event.pending_approval?,
      rejected: event.rejected?,
      attendees: event.rsvps.includes(:user).map { |r|
        { id: r.user&.id, name: r.user&.name }
      },
    }
  end

  def rsvp
    event = Event.find(params[:id])
    return render_error('Event not available', status: :forbidden) unless event.approved?

    existing = current_api_user.rsvps.find_by(event: event)
    if existing
      existing.destroy
      render json: { rsvped: false }
    else
      current_api_user.rsvps.create!(event: event)
      render json: { rsvped: true }
    end
  end

  # POST /api/v1/events — member submits an event for admin approval.
  # Day-pass-only users are not eligible; members (subscription / lease)
  # and admins can submit.
  def create
    user = current_api_user
    return render_error('You need an active membership or lease to submit events.', status: :forbidden) unless user_can_submit_events?(user)

    event = Event.new(
      title: params[:title]&.strip,
      description: params[:description]&.strip,
      location_string: params[:location_string]&.strip,
      starts_at: params[:starts_at].present? ? Time.parse(params[:starts_at]) : nil,
      ends_at: params[:ends_at].present? ? Time.parse(params[:ends_at]) : nil,
      user: user,
      location: current_location,
      submitted_via_app: true,
    )

    # Admins/managers who submit via app auto-approve their own events.
    if user.admin_or_manager?(current_location) || user.superadmin?
      event.approved_at = Time.current
    end

    if params[:image].present?
      event.image.attach(params[:image])
    end

    if event.save
      # Member / lease-holder submissions land pending — push to the
      # location's admins so they can review on AdminEvents + drop a
      # FeedItem for the Today feed. Admin self-submissions auto-approve
      # above and skip this fanout.
      if event.approved_at.nil?
        CreateNotificationsAsync.call(notifiable: event)
      end

      render json: {
        id: event.id,
        title: event.title,
        approved: event.approved?,
        pending_approval: event.pending_approval?,
        message: event.approved? ? 'Event published.' : 'Submitted! An admin will review it shortly.',
      }, status: :created
    else
      render_error(event.errors.full_messages.first)
    end
  rescue ArgumentError => e
    render_error("Invalid time: #{e.message}")
  end

  # GET /api/v1/events/my_submissions — member's own submissions w/ status.
  def my_submissions
    user = current_api_user
    mine = Event.where(user: user, location: current_location).order(created_at: :desc).limit(20)
    render json: mine.map { |e|
      {
        id: e.id,
        title: e.title,
        date: e.starts_at&.strftime("%B %e, %Y"),
        time: e.starts_at&.strftime("%l:%M %p")&.strip,
        status: e.approved? ? 'approved' : (e.rejected? ? 'rejected' : 'pending'),
      }
    }
  end

  private

  def user_can_submit_events?(user)
    user.has_active_subscription? ||
      user.has_active_lease?(current_location) ||
      user.admin_or_manager?(current_location) ||
      user.superadmin?
  end

  def event_card_json(e, user_rsvp_ids)
    {
      id: e.id,
      title: e.title,
      description: e.description,
      date: e.starts_at.strftime("%B %e, %Y"),
      time: e.starts_at.strftime("%l:%M %p").strip,
      location: e.location_string,
      image_url: (e.image.attached? ? url_for(e.image) : nil rescue nil),
      hosted_by: e.user&.name,
      rsvped: user_rsvp_ids.include?(e.id),
      rsvp_count: e.rsvps.count,
    }
  end
end
