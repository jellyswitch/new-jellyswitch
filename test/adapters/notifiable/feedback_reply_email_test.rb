require 'test_helper'

# Email fallback for admin Feedback replies: web/Concierge visitors have no
# app, so the push in send_notification can't reach them — the reply must go
# out by email. App users (any device token) keep getting push only.
class Notifiable::FeedbackReplyEmailTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @location = @operator.locations.first
    @admin    = users(:cowork_tahoe_admin)
    @visitor  = User.create!(
      email: "visitor+cx@example.com", name: "Widget Visitor", operator: @operator,
      original_location_id: @location.id, admin_created: true, password: "tempPass1!", phone: "555-0100",
    )
    @feedback = MemberFeedback.create!(
      user: @visitor, operator: @operator, location: @location,
      comment: "Question from the website Concierge: do you have standing desks?",
    )
  end

  def admin_reply
    FeedbackReply.create!(
      member_feedback: @feedback, user: @admin, operator: @operator,
      body: "We do — four of them, first come first served.",
    )
  end

  test "admin reply to a token-less member enqueues the email fallback" do
    reply = admin_reply
    assert_enqueued_email_with FeedbackReplyMailer, :admin_reply, params: { reply: reply } do
      Notifiable::FeedbackReply.new(reply).send(:send_email_fallback)
    end
  end

  test "no email when the member has an app token (push reaches them)" do
    @visitor.update!(ios_token: "tok123")
    assert_no_enqueued_emails do
      Notifiable::FeedbackReply.new(admin_reply).send(:send_email_fallback)
    end
  end

  test "no email for a member reply (staff use the admin inbox, not email)" do
    reply = FeedbackReply.create!(
      member_feedback: @feedback, user: @visitor, operator: @operator, body: "thanks!",
    )
    assert_no_enqueued_emails do
      Notifiable::FeedbackReply.new(reply).send(:send_email_fallback)
    end
  end

  test "mailer renders the reply with branded from and admin reply-to" do
    mail = FeedbackReplyMailer.with(reply: admin_reply).admin_reply

    assert_equal [@visitor.email], mail.to
    assert_equal [@admin.email], mail.reply_to
    assert_match @operator.name, mail.subject
    [mail.html_part.body.to_s, mail.text_part.body.to_s].each do |body|
      assert_match "four of them", body
      assert_match "reply to this email", body
    end
  end
end
