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

  test "inbox dismiss button asks for confirmation (accidental-dismiss guard)" do
    get member_feedbacks_path, env: default_env
    assert_select "##{ActionView::RecordIdentifier.dom_id(@conversation)} form[data-turbo-confirm]"
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

  test "restore clears dismissed_at and puts the conversation back on the inbox" do
    @conversation.update!(dismissed_at: Time.current)

    post restore_member_feedback_path(@conversation), env: default_env
    assert_nil @conversation.reload.dismissed_at

    get member_feedbacks_path, env: default_env
    assert_select "##{ActionView::RecordIdentifier.dom_id(@conversation)}", true,
      "a restored conversation should reappear in the inbox"
  end

  test "restore is staff-only — the thread's member cannot restore" do
    @conversation.update!(dismissed_at: Time.current)
    delete logout_path, env: default_env
    log_in @member

    post restore_member_feedback_path(@conversation), env: default_env
    assert_not_nil @conversation.reload.dismissed_at,
      "a member must not be able to restore a dismissed thread"
  end

  test "anonymous visit to a thread is quietly redirected, not a 500" do
    delete logout_path, env: default_env

    get member_feedback_path(@conversation), env: default_env
    assert_response :redirect
    assert_nil flash[:alert], "anonymous denials must not set a sticky flash"
  end

  # Regression: an archived member posting from the web chat card. The
  # archived-author guard (#731) refuses the thread, MemberFeedback::Save
  # failed before it put the record on the context, and the failure branch
  # re-rendered the form with nil — ActionView blew up with "First argument in
  # form cannot contain nil or be empty" (Honeybadger, Choose Folsom
  # Workspace). The refusal has to land as a 422 that says why.
  test "an archived member's post is refused with a 422, not a 500" do
    delete logout_path, env: default_env
    @member.member_feedbacks.destroy_all
    @member.update!(archived: true, current_location: @location)
    log_in @member

    assert_no_difference -> { MemberFeedback.where(user: @member).count } do
      post member_feedbacks_path,
           params: { member_feedback: { comment: "Can I still get in?" } },
           env: default_env
    end

    assert_response :unprocessable_entity
    assert_equal MemberFeedback::ARCHIVED_AUTHOR_MESSAGE, flash[:error]
    assert_select "form"
  end

  test "anonymous visit to an unknown thread id is not found, not a 500" do
    delete logout_path, env: default_env

    assert_raises(ActiveRecord::RecordNotFound) do
      get member_feedback_path(id: MemberFeedback.maximum(:id).to_i + 1), env: default_env
    end
  end
end
