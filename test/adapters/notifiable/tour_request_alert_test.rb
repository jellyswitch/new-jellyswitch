require 'test_helper'

class Notifiable::TourRequestAlertTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @location = @operator.locations.first
    @admin    = users(:cowork_tahoe_admin)
    @gm       = User.create!(
      email: "gm+tour@example.com", name: "GM Test", operator: @operator,
      role: User::GENERAL_MANAGER, current_location_id: @location.id,
      original_location_id: @location.id, admin_created: true, password: "tempPass1!", phone: "555-0000",
    )
    @requester = User.create!(
      email: "req+tour@example.com", name: "Req Test", operator: @operator,
      original_location_id: @location.id, admin_created: true, password: "tempPass1!", phone: "555-0001",
    )
    @activity = Activity.create!(
      user: @requester, operator: @operator, kind: "tour_request",
      occurred_at: Time.current, subject: @location, payload: { "message" => "Curious about hot desks" },
    )
    @notifiable = Notifiable::TourRequestAlert.new(@activity)
  end

  test "recipients includes operator admins" do
    assert_includes @notifiable.send(:recipients), @admin
  end

  test "recipients includes general managers at the requested location" do
    assert_includes @notifiable.send(:recipients), @gm
  end

  test "recipients excludes managers at other locations" do
    other_location = @operator.locations.create!(name: "Other", visible: true, time_zone: "Pacific Time (US & Canada)")
    other_gm = User.create!(
      email: "other-gm@example.com", name: "Other GM", operator: @operator,
      role: User::GENERAL_MANAGER, current_location_id: other_location.id,
      original_location_id: other_location.id, admin_created: true, password: "tempPass1!", phone: "555-9999",
    )
    refute_includes @notifiable.send(:recipients), other_gm
  end

  test "recipients de-duplicates if a user is both admin and GM" do
    @admin.update!(role: User::GENERAL_MANAGER, current_location_id: @location.id)
    recipients = @notifiable.send(:recipients)
    assert_equal recipients.uniq, recipients
  end

  test "should_send_notification? true only for tour_request kind" do
    assert @notifiable.send(:should_send_notification?)
    other = Activity.create!(user: @requester, operator: @operator, kind: "signup", occurred_at: Time.current, payload: {})
    refute Notifiable::TourRequestAlert.new(other).send(:should_send_notification?)
  end

  test "notify enqueues a visitor confirmation email to the requester" do
    assert_enqueued_email_with TourRequestMailer, :confirmation,
                               params: { activity: @activity } do
      @notifiable.send(:send_visitor_confirmation)
    end
  end

  test "no visitor confirmation for a non-tour_request activity" do
    other = Activity.create!(user: @requester, operator: @operator, kind: "signup",
                             occurred_at: Time.current, payload: {})
    assert_no_enqueued_emails do
      Notifiable::TourRequestAlert.new(other).send(:send_visitor_confirmation)
    end
  end

  test "message includes requester name and message preview" do
    msg = @notifiable.send(:message)
    assert_includes msg, "Req Test"
    assert_includes msg.downcase, "tour request"
  end
end
