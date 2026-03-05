class Events::Update
  include Interactor
  include Events::TimeParsing

  delegate :event, :event_params, :user, :location, to: :context

  def call
    params = context.event_params.merge!({
      user: user,
      location: location
    })

    if params[:starts_at].present?
      params[:starts_at] = parse_time_in_zone(params[:starts_at], location.time_zone)
    else
      context.fail!(message: "You must provide a start date for your event.")
    end

    if params[:ends_at].present?
      params[:ends_at] = parse_time_in_zone(params[:ends_at], location.time_zone)
    end

    if !event.update(params)
      context.fail!(message: "Could not update event.")
    end
  end
end