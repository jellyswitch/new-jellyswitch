require "test_helper"

# Push copy and audience for the four Day Office notifiables (ADR 0026).
# These are dispatched by explicit type string, so the factory mapping is part
# of the contract too — a typo there is a raise at job time, in a job fired
# from a door unlock.
class Notifiable::DayOfficeTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @location.update!(time_zone: "Pacific Time (US & Canada)",
                      working_day_start: "08:00", working_day_end: "18:00")
    @zone = ActiveSupport::TimeZone["Pacific Time (US & Canada)"]
  end

  # Returns [day_pass, hold, member].
  def assigned_pass(day:)
    ActsAsTenant.with_tenant(@operator) do
      member = create(:user, operator: @operator, original_location: @location,
                      current_location: @location, name: "Dana Reyes")
      bundle, = make_office_bundle(member: member)
      pass = DayPass.create!(user: member, billable: member, operator: @operator, location: @location,
                             day_pass_type: bundle.day_pass_type, day: day, imported: true)
      [pass, DayOffices::Allocator.allocate!(day_pass: pass), member]
    end
  end

  def adapter_for(record, type)
    NotifiableFactory.for(record, type)
  end

  # --- DayOfficeAssigned -------------------------------------------------

  test "assigned names the room and window, and says today only when it IS today" do
    # Fixed instant so "today" is unambiguous in the location's zone.
    travel_to @zone.parse("#{Date.current} 09:00") do
      pass, = assigned_pass(day: Date.current)
      adapter = adapter_for(pass, "DayOfficeAssigned")

      assert_equal "🔑 Office A is yours today, 8:00 AM–6:00 PM", adapter.send(:message)
      assert adapter.send(:should_send_notification?)
      assert_equal [pass.user], adapter.send(:recipients)
    end
  end

  test "assigned uses the pass's short date for a future day" do
    future = Date.current + 6
    travel_to @zone.parse("#{Date.current} 09:00") do
      pass, = assigned_pass(day: future)
      message = adapter_for(pass, "DayOfficeAssigned").send(:message)

      assert_includes message, "Office A is yours on #{future.strftime('%b %-d')},"
      assert_not_includes message, "today"
    end
  end

  test "assigned suppresses the push (without raising) once the hold is released" do
    pass, hold = assigned_pass(day: Date.current + 2)
    DayOffices::ReleaseHold.call(hold)
    adapter = adapter_for(pass.reload, "DayOfficeAssigned")

    assert_not adapter.send(:should_send_notification?)
    # Default#notify logs the message before consulting should_send_notification?,
    # so a nil hold must not blow up there.
    assert_nothing_raised { adapter.send(:message) }
    assert adapter.send(:message).present?, "message must stay non-blank (Default#validate! rejects blank)"
  end

  # --- walk-in pair ------------------------------------------------------

  test "walk-in member copy promises access, not an office" do
    travel_to @zone.parse("#{Date.current} 09:00") do
      pass, = assigned_pass(day: Date.current)
      adapter = adapter_for(pass, "DayOfficeUnavailable")

      assert_equal "No offices are left today — your pass still works; see staff.", adapter.send(:message)
      assert_equal [pass.user], adapter.send(:recipients)
      assert adapter.send(:should_send_notification?)
    end
  end

  # The same member adapter serves the reserve-time burn, which can be weeks
  # ahead of the date — "today" there would simply be false.
  test "the member copy carries the pass's date for a future-dated booking" do
    future = Date.current + 6
    travel_to @zone.parse("#{Date.current} 09:00") do
      pass, = assigned_pass(day: future)
      message = adapter_for(pass, "DayOfficeUnavailable").send(:message)

      assert_equal "No offices are left on #{future.strftime('%b %-d')} — your pass still works; see staff.",
                   message
      assert_not_includes message, "today"
    end
  end

  test "walk-in admin alert names the member and goes to that location's admins" do
    travel_to @zone.parse("#{Date.current} 09:00") do
      pass, _hold, member = assigned_pass(day: Date.current)
      adapter = adapter_for(pass, "DayOfficeUnassignedAlert")

      assert_equal "#{member.name} arrived on a Day Office pass but no office was free — " \
                   "reassign a room or restore the pass", adapter.send(:message)
      assert_equal @operator.users.relevant_admins_of_location(@location).to_a,
                   adapter.send(:recipients).to_a
      assert_equal({ type: "user", resource_id: member.id, path: "/users/#{member.id}" },
                   adapter.send(:deep_link_data))
    end
  end

  test "the booking admin alert carries the date and never says anyone arrived" do
    future = Date.current + 6
    travel_to @zone.parse("#{Date.current} 09:00") do
      pass, _hold, member = assigned_pass(day: future)
      adapter = adapter_for(pass, "DayOfficeUnassignedBookingAlert")
      message = adapter.send(:message)

      assert_equal "#{member.name} booked a Day Office for #{future.strftime('%b %-d')} but no office " \
                   "was free — reassign a room or restore the pass", message
      assert_not_includes message, "arrived"
      # Audience and deep link are inherited from the walk-in alert.
      assert_equal @operator.users.relevant_admins_of_location(@location).to_a,
                   adapter.send(:recipients).to_a
      assert_equal({ type: "user", resource_id: member.id, path: "/users/#{member.id}" },
                   adapter.send(:deep_link_data))
    end
  end

  test "a same-day booking alert says 'for today' rather than a redundant date" do
    travel_to @zone.parse("#{Date.current} 09:00") do
      pass, = assigned_pass(day: Date.current)

      assert_includes adapter_for(pass, "DayOfficeUnassignedBookingAlert").send(:message),
                      "booked a Day Office for today but no office was free"
    end
  end

  # --- DayOfficeReassigned -----------------------------------------------

  test "reassigned names the new room and deep-links to the PASS, not the hold" do
    future = Date.current + 4
    pass, hold = assigned_pass(day: future)
    adapter = adapter_for(hold, "DayOfficeReassigned")

    assert_equal "Your office for #{future.strftime('%b %-d')} is now Office A", adapter.send(:message)
    assert_equal [pass.user], adapter.send(:recipients)
    assert_equal({ type: "day_pass", resource_id: pass.id, path: "/day_passes/#{pass.id}" },
                 adapter.send(:deep_link_data))
  end

  # --- no feed items -----------------------------------------------------

  test "none of them write a feed item" do
    pass, hold = assigned_pass(day: Date.current)

    assert_no_difference "FeedItem.count" do
      adapter_for(pass, "DayOfficeAssigned").send(:create_feed_item)
      adapter_for(pass, "DayOfficeUnavailable").send(:create_feed_item)
      adapter_for(pass, "DayOfficeUnassignedAlert").send(:create_feed_item)
      adapter_for(pass, "DayOfficeUnassignedBookingAlert").send(:create_feed_item)
      adapter_for(hold, "DayOfficeReassigned").send(:create_feed_item)
    end
  end

  test "the factory maps every Day Office type string" do
    pass, hold = assigned_pass(day: Date.current)

    assert_instance_of Notifiable::DayOfficeAssigned, adapter_for(pass, "DayOfficeAssigned")
    assert_instance_of Notifiable::DayOfficeUnavailable, adapter_for(pass, "DayOfficeUnavailable")
    assert_instance_of Notifiable::DayOfficeUnassignedAlert, adapter_for(pass, "DayOfficeUnassignedAlert")
    assert_instance_of Notifiable::DayOfficeUnassignedBookingAlert,
                       adapter_for(pass, "DayOfficeUnassignedBookingAlert")
    assert_instance_of Notifiable::DayOfficeReassigned, adapter_for(hold, "DayOfficeReassigned")
  end
end
