require 'test_helper'

class SendNotificationsJobTest < ActiveJob::TestCase
  def setup
    @notifiable = reservations(:room_reservation)
    @notifiable_type = 'PaidRoomReservation'
    @notifiable_instance = mock('notifiable_instance')
  end

  test "perform calls NotifiableFactory with correct arguments" do
    NotifiableFactory.expects(:for).with(@notifiable, @notifiable_type).returns(@notifiable_instance)
    @notifiable_instance.expects(:notify)

    SendNotificationsJob.perform_now(@notifiable, @notifiable_type)
  end

  # If the notifiable is deleted between enqueue and execution, deserializing
  # the GlobalID raises ActiveJob::DeserializationError. The job must discard
  # it (not raise / retry ~25x). kind: :checkin is non-significant, so creating
  # the Activity doesn't enqueue its own alert.
  test "discards instead of raising when the notifiable was deleted before run" do
    user = users(:cowork_tahoe_member)
    activity = Activity.create!(user: user, operator: user.operator, kind: :checkin,
                                occurred_at: Time.current, payload: {})
    SendNotificationsJob.perform_later(activity, "PointOfContactAlert")
    activity.delete

    NotifiableFactory.expects(:for).never
    assert_nothing_raised { perform_enqueued_jobs }
  end
end
