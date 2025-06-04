require 'test_helper'

class Notifiable::WeeklyUpdateTest < ActiveSupport::TestCase
  def setup
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @user = users(:cowork_tahoe_admin)
    
    @weekly_update = WeeklyUpdate.new(
      operator: @operator,
      location: @location,
      week_start: 1.week.ago,
      week_end: Time.current,
      blob: {
        "day_passes" => 5,
        "checkins" => 10,
        "admins" => [@user.id]
      }
    )
    @weekly_update.save!
    
    @notifiable = Notifiable::WeeklyUpdate.new(@weekly_update)
  end

  test "create_feed_item creates a feed item with correct attributes" do
    FeedItemCreator.expects(:create_feed_item).with(
      @operator, 
      @location, 
      instance_of(User), 
      { type: "weekly-update", weekly_update_id: @weekly_update.id },
      created_at: @weekly_update.created_at
    )

    @notifiable.send(:create_feed_item)
  end

  test "should_send_notification? returns true" do
    assert @notifiable.send(:should_send_notification?)
  end

  test "message returns the correct notification message" do
    expected_message = "Your weekly update has been posted in the feed. Take a look!"
    assert_equal expected_message, @notifiable.send(:message)
  end

  test "recipients returns the correct recipients" do
    @operator.users.expects(:relevant_admins_of_location).with(@location).returns([@user])
    
    assert_equal [@user], @notifiable.send(:recipients)
  end

  test "ios notification is sent when operator has both push certificate and bundle_id" do
    # Setup operator with both certificate and bundle_id
    @operator.stubs(:push_notification_certificate).returns(mock(attached?: true))
    @operator.stubs(:bundle_id).returns("com.example.app")
    
    # Get the actual recipients to know how many to expect
    recipients = @notifiable.send(:recipients)
    recipients.each { |user| user.stubs(:ios_token).returns("some_token") }
    
    # Mock IosNotification with proper response chain
    response_mock = mock
    response_mock.stubs(:ok?).returns(true)
    response_mock.stubs(:body).returns("success")
    
    ios_notification_mock = mock
    ios_notification_mock.expects(:send!).returns(response_mock).times(recipients.count)
    IosNotification.expects(:new).returns(ios_notification_mock).times(recipients.count)
    
    @notifiable.send(:ios)
  end

  test "ios notification is not sent when operator has certificate but no bundle_id" do
    # Setup operator with certificate but no bundle_id
    @operator.stubs(:push_notification_certificate).returns(mock(attached?: true))
    @operator.stubs(:bundle_id).returns(nil)
    @operator.stubs(:name).returns("Test Operator")
    
    # Mock recipients
    @notifiable.stubs(:recipients).returns([@user])
    
    # IosNotification should not be called
    IosNotification.expects(:new).never
    
    @notifiable.send(:ios)
  end

  test "ios notification is not sent when operator has bundle_id but no certificate" do
    # Setup operator with bundle_id but no certificate
    @operator.stubs(:push_notification_certificate).returns(mock(attached?: false))
    @operator.stubs(:bundle_id).returns("com.example.app")
    @operator.stubs(:name).returns("Test Operator")
    
    # Mock recipients
    @notifiable.stubs(:recipients).returns([@user])
    
    # IosNotification should not be called
    IosNotification.expects(:new).never
    
    @notifiable.send(:ios)
  end

  test "ios notification is not sent when operator has neither certificate nor bundle_id" do
    # Setup operator with neither certificate nor bundle_id
    @operator.stubs(:push_notification_certificate).returns(mock(attached?: false))
    @operator.stubs(:bundle_id).returns(nil)
    @operator.stubs(:name).returns("Test Operator")
    
    # Mock recipients
    @notifiable.stubs(:recipients).returns([@user])
    
    # IosNotification should not be called
    IosNotification.expects(:new).never
    
    @notifiable.send(:ios)
  end
end
