class Events::Going
  include Interactor

  delegate :event, :user, to: :context

  def call
    if event.rsvps

    if !event.rsvps.create!(user: user)
      context.fail!(message: "Could not RSVP to this event.")
    end
  end
end