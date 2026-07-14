require "test_helper"

class UserMailerDayPassRescheduledTest < ActionMailer::TestCase
  setup do
    @pass = day_passes(:cowork_tahoe_day_pass)
    @pass.update_columns(location_id: locations(:cowork_tahoe_location).id,
                         day: Date.new(2026, 8, 21))
    @old_day = Date.new(2026, 8, 14)
  end

  test "sends to the pass holder with both dates and the location" do
    mail = UserMailer.day_pass_rescheduled(@pass.id, @old_day)

    assert_equal [@pass.user.email], mail.to
    assert_match "August 21, 2026", mail.subject
    body = mail.body.to_s
    assert_match "August 21, 2026", body
    assert_match "August 14, 2026", body
    assert_match locations(:cowork_tahoe_location).name, body
  end

  test "quietly no-ops when the pass is gone" do
    mail = UserMailer.day_pass_rescheduled(0, @old_day)
    assert_nil mail.to
  end
end
