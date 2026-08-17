require "test_helper"

# Timeline cards read the denormalized activity payload and never the subject
# (ADR 0001). Now that reservation cards show the BOOKED window rather than the
# booking timestamp, a stale payload is a wrong answer on screen — so edits,
# early ends, and cancels have to write back.
class ActivityPayloadFreshnessTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @room     = rooms(:small_meeting_room)
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      @reservation = Reservation.create!(user: @member, room: @room,
                                         datetime_in: 3.days.from_now.change(hour: 10),
                                         hours: 1, minutes: 60)
    end
  end

  def reservation_payload
    Activity.find_by!(kind: "reservation", subject_type: "Reservation", subject_id: @reservation.id).payload
  end

  test "logs the booked window and duration at create" do
    payload = reservation_payload

    assert_equal 60, payload["minutes"]
    assert_equal @reservation.datetime_in.iso8601, payload["datetime_in"]
    assert_equal false, payload["cancelled"]
  end

  test "moving a reservation rewrites the card's window" do
    moved_to = @reservation.datetime_in + 2.days
    @reservation.update!(datetime_in: moved_to)

    assert_equal @reservation.reload.datetime_in.iso8601, reservation_payload["datetime_in"]
  end

  test "ending early rewrites the card's duration" do
    @reservation.update!(minutes: 20, ended_early: true)

    assert_equal 20, reservation_payload["minutes"]
  end

  test "cancelling marks the card cancelled rather than leaving a live booking" do
    @reservation.update!(cancelled: true)

    assert_equal true, reservation_payload["cancelled"]
  end

  test "an unrelated edit leaves the payload alone" do
    before = reservation_payload
    @reservation.update!(note: "moved to the corner table")

    assert_equal before, reservation_payload
  end

  test "buying a bundle logs a timeline card carrying the pack size" do
    ActsAsTenant.with_tenant(@operator) do
      type = DayPassType.create!(operator: @operator, location: @location, name: "10-Pack",
                                 amount_in_cents: 40000, quantity: 10, available: true, visible: true)
      bundle = DayPassBundle.create!(user: @member, operator: @operator, location: @location,
                                     day_pass_type: type, quantity_purchased: 10, passes_remaining: 10,
                                     purchased_at: Time.current)

      activity = Activity.find_by(kind: "day_pass_bundle", subject_type: "DayPassBundle", subject_id: bundle.id)

      assert_not_nil activity, "bundle purchase should appear on the member timeline"
      assert_equal 10, activity.payload["quantity"]
      assert_equal "10-Pack", activity.payload["day_pass_type_name"]
      assert_equal @member.id, activity.user_id
    end
  end
end
