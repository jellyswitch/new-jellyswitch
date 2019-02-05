class CreateMemberFeedback
  include Interactor

  def call
    member_feedback = MemberFeedback.new(context.member_feedpack_params)
    member_feedback.user = context.user
    member_feedback.operator = context.operator

    if !member_feedback.save
      context.fail!(message: "Couldn't submit feedback.")
    end

    context.member_feedback = member_feedback

    feed_item = FeedItem.new
    feed_item.operator = context.operator
    feed_item.user = context.user
    feed_item.blob = {type: "feedback", member_feedback_id: member_feedback.id}
    if !feed_item.save
      context.fail!(message: "Unable to generate feed item.")
    end
  end
end