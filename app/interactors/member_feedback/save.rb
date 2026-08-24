class MemberFeedback::Save
  include Interactor
  include FeedItemCreator

  def call
    member_feedback = MemberFeedback.new(context.member_feedback_params)
    member_feedback.user = context.user
    member_feedback.operator = context.operator
    member_feedback.location = context.location

    # Expose the record BEFORE the failure check. The web #create failure path
    # re-renders the form with `result.member_feedback`; when this was only
    # assigned on success, a refused thread (e.g. the archived-author guard,
    # #731) handed the view a nil and form_for blew up with "First argument in
    # form cannot contain nil or be empty" — a 500 instead of the 422 that
    # states why. Carrying the invalid record through also shows its
    # validation errors inline.
    context.member_feedback = member_feedback

    if !member_feedback.save
      context.fail!(message: member_feedback.errors.full_messages.first || "Couldn't submit feedback.")
    end

    context.notifiable = member_feedback
  end
end
