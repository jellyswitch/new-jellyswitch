class Events::Create
  include Interactor

  delegate :event_params, :user, :location, to: :context

  def call
    params = context.event_params.merge!({
      user: user,
      location: location
    })

    event = Event.new(params)
    
    if event.save
      context.event = event
    else
      context.fail!(message: "Could not create event.")
    end
  end
end