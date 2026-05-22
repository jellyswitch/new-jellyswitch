class MemberFeedback::EnsureHostGreeting
  include Interactor

  # Makes the space host's "Hi! Any questions?" prompt feel like a real
  # message: when a visitor lands on the choose page (or hits the mobile
  # dashboard) without an existing thread at this location, we create a
  # MemberFeedback owned by the visitor and immediately drop a FeedbackReply
  # from the host into it. The greeting then renders both on the host-chat
  # card and inside My Messages — same conversation, persistent context.
  #
  # Idempotent: if a thread already exists for this user+location, it's a
  # no-op. Safe to call on every page load.
  def call
    user = context.user
    location = context.location
    operator = context.operator
    return if user.blank? || location.blank? || operator.blank?
    return if user.member_feedbacks.where(location: location).exists?

    host = context.host
    return if host.blank?

    # Empty comment because the host is "messaging first" — the show view
    # skips rendering a blank original-message bubble so the conversation
    # starts with the host's greeting.
    feedback = MemberFeedback.new(
      user: user,
      operator: operator,
      location: location,
      comment: nil,
      anonymous: false,
    )
    return unless feedback.save

    greeting = context.greeting.presence || default_greeting(user, location)
    FeedbackReply.create!(
      member_feedback: feedback,
      user: host,
      operator: operator,
      body: greeting,
    )

    context.member_feedback = feedback
  end

  private

  def default_greeting(user, location)
    first_name = user.name.to_s.split.first.presence
    intro = first_name ? "Hi #{first_name}!" : "Hi there!"
    "#{intro} Welcome to #{location.name} — I'm here whenever you need a hand. " \
      "Day-pass logistics, room availability, what to expect when you arrive… ask anything."
  end
end
