require 'test_helper'

class TourRequestMailerTest < ActionMailer::TestCase
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @location = @operator.locations.first
    @recipient = users(:cowork_tahoe_admin)
    @requester = User.create!(
      email: "req+mailer@example.com", name: "Req M", operator: @operator,
      original_location_id: @location.id, admin_created: true, password: "tempPass1!", phone: "555-0002",
    )
    @activity = Activity.create!(
      user: @requester, operator: @operator, kind: "tour_request",
      occurred_at: Time.current, subject: @location,
      payload: { "message" => "Looking for office space for 3", "preferred_time" => "Next Tuesday afternoon" },
    )
  end

  test "new_request email has correct to/subject and body" do
    mail = TourRequestMailer.with(recipient: @recipient, activity: @activity).new_request

    assert_equal [@recipient.email], mail.to
    assert_match "New tour request", mail.subject
    assert_match @requester.name, mail.subject

    html_body = mail.html_part.body.to_s
    text_body = mail.text_part.body.to_s

    assert_match @requester.name, html_body
    assert_match @requester.email, html_body
    assert_match "Looking for office space for 3", html_body
    assert_match @location.name, html_body

    assert_match @requester.name, text_body
    assert_match @requester.email, text_body
    assert_match "Looking for office space for 3", text_body
    assert_match @location.name, text_body

    assert_match "Next Tuesday afternoon", html_body
    assert_match "Next Tuesday afternoon", text_body
  end
  test "confirmation email goes to the requester with branded from and tour details" do
    mail = TourRequestMailer.with(activity: @activity).confirmation

    assert_equal [@requester.email], mail.to
    assert_match "Your tour request", mail.subject
    assert_match @operator.name, mail.subject

    [mail.html_part.body.to_s, mail.text_part.body.to_s].each do |body|
      assert_match @requester.name, body
      assert_match @location.name, body
      assert_match "Next Tuesday afternoon", body
    end
  end

  test "confirmation without a preferred time still promises follow-up" do
    @activity.update!(payload: { "message" => "hi" })
    mail = TourRequestMailer.with(activity: @activity).confirmation

    assert_match(/reach out shortly/i, mail.text_part.body.to_s)
  end

end
