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

  test "android notification is sent when operator has both firebase key and project_id" do
    # Get the actual recipients and manually set their android tokens in the database
    recipients = @notifiable.send(:recipients)
    recipients.each { |user| user.update!(android_token: "android_device_token") }
    
    # Setup operator with both firebase key and project_id
    # Need to allow download to be called multiple times (once per recipient)
    firebase_key_mock = mock
    firebase_key_mock.stubs(:attached?).returns(true)
    firebase_key_mock.stubs(:download).returns("firebase_key_content")
    @operator.stubs(:android_push_notification_key).returns(firebase_key_mock)
    @operator.stubs(:firebase_project_id).returns("test-project-id")
    
    # Mock FCM - expect it to be called for each recipient with android token
    fcm_mock = mock
    fcm_mock.expects(:send_v1).with({
      "token": "android_device_token",
      "notification": {
        "title": @notifiable.send(:message),
        "body": @notifiable.send(:message)
      }
    }).times(recipients.count)
    
    FCM.expects(:new).with('', instance_of(StringIO), "test-project-id").returns(fcm_mock).times(recipients.count)
    
    @notifiable.send(:android)
  end

  test "android notification is not sent when operator has firebase key but no project_id" do
    # Setup operator with firebase key but no project_id
    @operator.stubs(:android_push_notification_key).returns(mock(attached?: true))
    @operator.stubs(:firebase_project_id).returns(nil)
    @operator.stubs(:name).returns("Test Operator")
    
    # Mock recipients
    @notifiable.stubs(:recipients).returns([@user])
    
    # FCM should not be called
    FCM.expects(:new).never
    
    @notifiable.send(:android)
  end

  test "android notification is not sent when operator has project_id but no firebase key" do
    # Setup operator with project_id but no firebase key
    @operator.stubs(:android_push_notification_key).returns(mock(attached?: false))
    @operator.stubs(:firebase_project_id).returns("test-project-id")
    @operator.stubs(:name).returns("Test Operator")
    
    # Mock recipients
    @notifiable.stubs(:recipients).returns([@user])
    
    # FCM should not be called
    FCM.expects(:new).never
    
    @notifiable.send(:android)
  end

  test "android notification is not sent when operator has neither firebase key nor project_id" do
    # Setup operator with neither firebase key nor project_id
    @operator.stubs(:android_push_notification_key).returns(mock(attached?: false))
    @operator.stubs(:firebase_project_id).returns(nil)
    @operator.stubs(:name).returns("Test Operator")
    
    # Mock recipients
    @notifiable.stubs(:recipients).returns([@user])
    
    # FCM should not be called
    FCM.expects(:new).never
    
    @notifiable.send(:android)
  end

  test "android notification is not sent when user has no android token" do
    # Ensure recipients have no android tokens in the database
    recipients = @notifiable.send(:recipients)
    recipients.each { |user| user.update!(android_token: nil) }
    
    # Setup operator with both firebase key and project_id
    firebase_key_mock = mock
    firebase_key_mock.stubs(:attached?).returns(true)
    firebase_key_mock.stubs(:download).returns("firebase_key_content")
    @operator.stubs(:android_push_notification_key).returns(firebase_key_mock)
    @operator.stubs(:firebase_project_id).returns("test-project-id")
    
    # FCM object should not be created since users have no token
    FCM.expects(:new).never
    
    @notifiable.send(:android)
  end
end
