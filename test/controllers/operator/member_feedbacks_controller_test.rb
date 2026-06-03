require "test_helper"

class Operator::MemberFeedbacksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin    = users(:cowork_tahoe_admin)
    @member   = users(:cowork_tahoe_member)
    @operator = @admin.operator
    @location = locations(:cowork_tahoe_location)
    @admin.update!(current_location: @location)
    log_in @admin

    # A host-greeting-only thread: comment nil, only a staff reply.
    @greeting_only = MemberFeedback.create!(operator: @operator, location: @location, user: @member, comment: nil)
    FeedbackReply.create!(member_feedback: @greeting_only, user: @admin, operator: @operator, body: "Hi! Any questions?")

    # A real conversation: the member replied.
    @conversation = MemberFeedback.create!(operator: @operator, location: @location, user: @member, comment: nil)
    FeedbackReply.create!(member_feedback: @conversation, user: @admin, operator: @operator, body: "Hi!")
    FeedbackReply.create!(member_feedback: @conversation, user: @member, operator: @operator, body: "Yes — what are the hours?")
  end

  test "index shows conversations the member engaged in, not greeting-only threads" do
    get member_feedbacks_path, env: default_env
    assert_response :success
    assert_select "##{ActionView::RecordIdentifier.dom_id(@conversation)}"
    assert_select "##{ActionView::RecordIdentifier.dom_id(@greeting_only)}", false,
      "host-greeting-only threads should not appear in the admin inbox"
  end

  test "dismiss hides the conversation and sets dismissed_at" do
    post dismiss_member_feedback_path(@conversation), env: default_env
    assert_not_nil @conversation.reload.dismissed_at

    get member_feedbacks_path, env: default_env
    assert_select "##{ActionView::RecordIdentifier.dom_id(@conversation)}", false,
      "a dismissed conversation should drop off the inbox"
  end

  test "a new reply resurfaces a dismissed conversation on the inbox" do
    @conversation.update!(dismissed_at: Time.current)
    FeedbackReply.create!(member_feedback: @conversation, user: @member, operator: @operator, body: "still there?")

    get member_feedbacks_path, env: default_env
    assert_select "##{ActionView::RecordIdentifier.dom_id(@conversation)}", true,
      "a restarted conversation should come back to the inbox"
  end
end
