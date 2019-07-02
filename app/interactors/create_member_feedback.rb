# typed: true
class CreateMemberFeedback
  include Interactor
  include FeedItemCreator

  def call
    member_feedback = MemberFeedback.new(context.member_feedback_params)
    member_feedback.user = context.user
    member_feedback.operator = context.operator

    if !member_feedback.save
      context.fail!(message: "Couldn't submit feedback.")
    end

    context.member_feedback = member_feedback

    blob = {type: "feedback", member_feedback_id: member_feedback.id}
    create_feed_item(context.operator, context.user, blob)

    message = "New member feedback"

    result = Notifications::PushNotifier.call(
      message: message,
      operator: context.operator
    )

    if !result.success?
      Rollbar.error("Error pushing notification: #{result.message}")
    end
  end
end