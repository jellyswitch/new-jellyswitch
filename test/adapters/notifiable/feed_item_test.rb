require "test_helper"

class Notifiable::FeedItemTest < ActiveSupport::TestCase
  def setup
    @location = locations(:cowork_tahoe_location)
    @member   = users(:cowork_tahoe_member)
    @operator = @member.operator
  end

  # Regression: the mobile subscription endpoints (pause/unpause/upgrade/cancel)
  # stored a bare String blob. jsonb persists that as a scalar, so on reload
  # `blob` comes back as a Ruby String. Notifiable::FeedItem#message and
  # #should_send_notification? called `blob&.dig("type")`, which raised
  # NoMethodError: undefined method `dig' for an instance of String in
  # SendNotificationsJob#perform.
  test "does not raise when blob is a non-Hash (String) scalar" do
    item = FeedItem.create!(
      operator: @operator, location: @location, user: @member,
      blob: "Paused for 5 days via mobile app",
    )
    item.reload
    assert_instance_of String, item.blob, "jsonb should round-trip the scalar back to a String"

    notifiable = Notifiable::FeedItem.new(item)
    assert_nothing_raised do
      notifiable.send(:should_send_notification?)
      notifiable.send(:message)
    end
  end

  test "daily-digest blob still produces the digest summary" do
    item = FeedItem.create!(
      operator: @operator, location: @location, user: @member,
      blob: { "type" => "daily-digest", "day_pass_count" => 2, "reservation_count" => 1, "total_revenue_cents" => 4500 },
    )

    notifiable = Notifiable::FeedItem.new(item)
    msg = notifiable.send(:message)

    assert_match "2 day passes", msg
    assert_match "1 reservation", msg
    assert_match "$45.00", msg
  end
end
