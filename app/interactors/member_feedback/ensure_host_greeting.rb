class MemberFeedback::EnsureHostGreeting
  include Interactor

  # Seeds the space host's "Hi! Any questions?" greeting as the first
  # message of a brand-new thread. Called at FIRST-MESSAGE time (the
  # member_feedbacks #create paths) — NOT on page view. The chat card
  # renders the greeting client-side without a thread; a MemberFeedback
  # only exists once the visitor actually replies, so the admin inbox
  # holds real conversations instead of one-sided auto-welcomes.
  #
  # Idempotent: if a thread already exists for this user+location, it's a
  # no-op.

  # The greeting is a SIGNUP welcome, not a feature announcement: only
  # accounts younger than this are greeted. Without the gate, every
  # long-standing member's first dashboard load after the greeting feature
  # shipped (or after re-logging in on a fresh install) minted them a
  # "Welcome to <space>!" message + unread badge years into their
  # membership. Once they have the lay of the land, they know what to do.
  NEW_MEMBER_WINDOW = 7.days

  def call
    user = context.user
    location = context.location
    operator = context.operator
    return if user.blank? || location.blank? || operator.blank?
    return if user.created_at.blank? || user.created_at < NEW_MEMBER_WINDOW.ago
    return if user.member_feedbacks.where(location: location).exists?

    host = context.host
    return if host.blank?
    # An archived host can't author the greeting (FeedbackReply refuses
    # archived authors, #731). space_host_for no longer hands one out, but
    # this interactor takes any host — skip the greeting rather than raise;
    # the caller then opens a plain thread from the member's own message.
    return if host.archived?

    # One transaction, no bangs: if the greeting can't save for any reason,
    # the empty thread shell must not survive without it — a create! here
    # once turned a refused greeting author into a 500 AND left an orphan
    # thread behind (Cowork Tahoe, 2026-08-19).
    feedback = nil
    ActiveRecord::Base.transaction do
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
      raise ActiveRecord::Rollback unless feedback.save

      greeting = context.greeting.presence || default_greeting(user, location)
      reply = FeedbackReply.new(
        member_feedback: feedback,
        user: host,
        operator: operator,
        body: greeting,
      )
      unless reply.save
        feedback = nil
        raise ActiveRecord::Rollback
      end
    end
    return if feedback.nil? || !feedback.persisted?

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
