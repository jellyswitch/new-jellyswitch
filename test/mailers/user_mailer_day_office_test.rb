require "test_helper"

# The Day Office confirmation family (ADR 0026). Every one of these mails is
# a promise about a specific room on a specific day, so the two things worth
# pinning are that the details are actually IN the body, and that the mail
# does not go out at all once the promise stops being true.
class UserMailerDayOfficeTest < ActionMailer::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @location.update!(time_zone: "Pacific Time (US & Canada)",
                      working_day_start: "08:00", working_day_end: "18:00")
    @day = Date.current + 9
  end

  # Returns [day_pass, hold, member].
  def assigned_pass(day: @day)
    ActsAsTenant.with_tenant(@operator) do
      member = create(:user, operator: @operator, original_location: @location,
                      current_location: @location, name: "Dana Reyes")
      bundle, = make_office_bundle(member: member)
      pass = DayPass.create!(user: member, billable: member, operator: @operator, location: @location,
                             day_pass_type: bundle.day_pass_type, day: day, imported: true)
      [pass, DayOffices::Allocator.allocate!(day_pass: pass), member]
    end
  end

  # --- day_office_confirmation -------------------------------------------

  test "confirmation carries room, date, window, location and the app CTA" do
    pass, hold, member = assigned_pass

    mail = UserMailer.day_office_confirmation(pass.id)

    assert_equal [member.email], mail.to
    assert_equal "Your Day Office: Office A on #{@day.strftime('%B %-e')}", mail.subject
    body = mail.body.to_s
    assert_match "Office A", body
    assert_match @day.strftime("%B"), body
    assert_match hold.window_label, body
    assert_match @location.name, body
    assert_match "Open the #{@operator.name} app to unlock the door", body
  end

  test "confirmation renders the store badges when the operator has app links" do
    @operator.update!(ios_url: "https://apps.apple.com/app/id1", android_url: "https://play.google.com/store/apps/details?id=x")
    pass, = assigned_pass

    body = UserMailer.day_office_confirmation(pass.id).body.to_s

    assert_match "apps.apple.com", body
    assert_match "play.google.com", body
  end

  test "confirmation does not send once the hold is released" do
    pass, hold = assigned_pass
    DayOffices::ReleaseHold.call(hold)

    mail = UserMailer.day_office_confirmation(pass.id)

    assert_nil mail.to, "a released hold has nothing left to confirm"
  end

  test "confirmation quietly no-ops when the pass is gone" do
    assert_nil UserMailer.day_office_confirmation(0).to
  end

  # --- day_office_reassigned ---------------------------------------------

  test "reassignment names both rooms, the date and the window" do
    _pass, hold, member = assigned_pass

    mail = UserMailer.day_office_reassigned(hold.id, "Office B")

    assert_equal [member.email], mail.to
    assert_equal "Your office for #{@day.strftime('%B %-e')} is now Office A", mail.subject
    body = mail.body.to_s
    assert_match "Office A", body
    assert_match "Office B", body
    assert_match @day.strftime("%B"), body
    assert_match hold.window_label, body
  end

  test "reassignment renders without an old room name" do
    _pass, hold = assigned_pass

    mail = UserMailer.day_office_reassigned(hold.id, nil)

    assert_match "Office A", mail.body.to_s
  end

  test "reassignment quietly no-ops when the hold is gone" do
    assert_nil UserMailer.day_office_reassigned(0, "Office B").to
  end

  # --- day_pass_rescheduled gains an office line -------------------------

  test "the reschedule email names the office when the pass holds one" do
    pass, hold = assigned_pass

    mail = UserMailer.day_pass_rescheduled(pass.id, @day - 3)

    body = mail.body.to_s
    assert_match "Your office:", body
    assert_match "Office A", body
    assert_match hold.window_label, body
  end

  test "the reschedule email is unchanged for a standard pass" do
    pass = day_passes(:cowork_tahoe_day_pass)
    pass.update_columns(location_id: @location.id, day: @day)

    body = UserMailer.day_pass_rescheduled(pass.id, @day - 3).body.to_s

    assert_no_match(/Your office:/, body)
  end
end
