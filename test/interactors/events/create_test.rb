require "test_helper"

# Approval-state coverage for Events::Create.
# Admin / manager / superadmin submissions auto-publish (approved_at
# stamped now). Member + lease-holder submissions land pending so an
# admin can review on /admin/events.
#
# Mirrors the existing Api::V1::EventsController#create behavior — the
# web flow had been letting admins create events that stayed
# pending_approval forever, which silently broke the events list for
# every web-flow admin submission.
class Events::CreateTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
  end

  # The interactor parses datetimes via strptime("%m/%d/%Y %l:%M %p"),
  # matching the format the operator events form posts.
  def base_params
    starts = 1.day.from_now
    ends   = starts + 2.hours
    fmt    = "%m/%d/%Y %l:%M %p"
    {
      title:       "Pool tournament",
      description: "Friendly Friday face-off.",
      starts_at:   starts.strftime(fmt),
      ends_at:     ends.strftime(fmt),
    }
  end

  test "admin submissions auto-approve" do
    result = Events::Create.call(
      user: users(:cowork_tahoe_admin),
      location: @location,
      event_params: ActionController::Parameters.new(base_params).permit!,
    )
    assert result.success?, result.message
    refute_nil result.event.approved_at, "admin event must auto-publish"
  end

  test "general manager submissions auto-approve" do
    result = Events::Create.call(
      user: users(:cowork_tahoe_general_manager),
      location: @location,
      event_params: ActionController::Parameters.new(base_params).permit!,
    )
    assert result.success?, result.message
    refute_nil result.event.approved_at
  end

  test "member submissions land pending for admin review" do
    result = Events::Create.call(
      user: users(:cowork_tahoe_member),
      location: @location,
      event_params: ActionController::Parameters.new(base_params).permit!,
    )
    assert result.success?, result.message
    assert_nil result.event.approved_at,
      "member-proposed events must land pending so an admin can review"
  end

  test "member submissions drop a FeedItem so admins see them in the feed" do
    # CreateNotificationsAsync enqueues SendNotificationsJob; flush
    # inline so the FeedItem hits the DB during the test.
    perform_enqueued_jobs do
      assert_difference -> { FeedItem.where("blob ->> 'type' = ?", "event-proposed").count }, +1 do
        Events::Create.call(
          user: users(:cowork_tahoe_member),
          location: @location,
          event_params: ActionController::Parameters.new(base_params).permit!,
        )
      end
    end
  end

  test "admin auto-approved submissions do not fan out a pending-event notification" do
    perform_enqueued_jobs do
      assert_no_difference -> { FeedItem.where("blob ->> 'type' = ?", "event-proposed").count } do
        Events::Create.call(
          user: users(:cowork_tahoe_admin),
          location: @location,
          event_params: ActionController::Parameters.new(base_params).permit!,
        )
      end
    end
  end
end
