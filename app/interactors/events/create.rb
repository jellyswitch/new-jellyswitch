class Events::Create
  include Interactor

  delegate :event_params, :user, :location, to: :context

  def call
    params = context.event_params.merge!({
      user: user,
      location: location
    })

    if params[:starts_at].present?
      params[:starts_at] = Time.strptime(params[:starts_at], "%m/%d/%Y %l:%M %p")
    else
      context.fail!(message: "You must provide a start date for your event.")
    end

    if params[:ends_at].present?
      params[:ends_at] = Time.strptime(params[:ends_at], "%m/%d/%Y %l:%M %p")
    end

    event = Event.new(params)
    
    if event.save
      context.event = event
    else
      context.fail!(message: "Could not create event.")
    end
  end
end