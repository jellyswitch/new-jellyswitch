require "test_helper"

# Archiving is the admin's "deactivate" gesture, but archived users can still
# log in by design — and nothing stopped them from messaging, so archiving a
# user flooding the inbox changed nothing (LaTasha, Untethered, 2026-08).
# The model layer now refuses archived AUTHORS on new threads and replies,
# while staff answering into an archived member's old thread still works.
class ArchivedUserCannotMessageTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @admin    = users(:cowork_tahoe_admin)
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
    end
  end

  def build_thread(author)
    MemberFeedback.new(user: author, operator: @operator, location: @location, comment: "hello")
  end

  def thread_owned_by(author)
    MemberFeedback.create!(user: author, operator: @operator, location: @location, comment: "hi")
  end

  test "an archived user cannot open a thread" do
    @member.update!(archived: true)

    feedback = build_thread(@member)

    assert_not feedback.save
    assert_includes feedback.errors.full_messages.first, "no longer active"
  end

  test "an archived user cannot reply into their existing thread" do
    thread = thread_owned_by(@member)
    @member.update!(archived: true)

    reply = FeedbackReply.new(member_feedback: thread, user: @member, operator: @operator, body: "more")

    assert_not reply.save
    assert_includes reply.errors.full_messages.first, "no longer active"
  end

  test "an active member can open a thread and reply" do
    thread = thread_owned_by(@member)
    reply = FeedbackReply.new(member_feedback: thread, user: @member, operator: @operator, body: "another")

    assert reply.save, reply.errors.full_messages.inspect
  end

  # Archiving mutes the member, not the conversation record: staff may still
  # need to send a final "your account is closed" note into the old thread.
  test "staff can still reply into an archived member's thread" do
    thread = thread_owned_by(@member)
    @member.update!(archived: true)

    reply = FeedbackReply.new(member_feedback: thread, user: @admin, operator: @operator, body: "Take care!")

    assert reply.save, reply.errors.full_messages.inspect
  end

  test "existing rows from a since-archived author are untouched on update" do
    thread = thread_owned_by(@member)
    @member.update!(archived: true)

    assert thread.update(dismissed_at: Time.current), "on: :create must not block updates"
  end

  test "the reply interactor surfaces the clear message, not the generic one" do
    thread = thread_owned_by(@member)
    @member.update!(archived: true)

    result = MemberFeedback::CreateReply.call(
      member_feedback: thread, user: @member, operator: @operator, body: "again"
    )

    assert result.failure?
    assert_equal MemberFeedback::ARCHIVED_AUTHOR_MESSAGE, result.message
  end

  # Called at first-message time for new accounts; an archived new account
  # must get a quiet no-op (return unless feedback.save), never a raise.
  test "EnsureHostGreeting no-ops for an archived brand-new user" do
    @member.update!(archived: true)

    result = nil
    assert_nothing_raised do
      result = MemberFeedback::EnsureHostGreeting.call(
        user: @member, location: @location, operator: @operator, host: @admin
      )
    end
    assert_nil result.member_feedback
    assert_equal 0, @member.member_feedbacks.count
  end
end
