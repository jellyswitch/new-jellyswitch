require "test_helper"

class UserMailerMembershipCancellationTest < ActionMailer::TestCase
  setup do
    ActionMailer::Base.default_url_options[:host] = "test.example.com"
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @subscription = subscriptions(:cowork_tahoe_subscription)
    @user = @subscription.subscribable
  end

  test "sends to the member's email" do
    mail = UserMailer.membership_cancellation_email(@user, @operator, @subscription, @location, immediate: false)
    assert_equal [@user.email], mail.to
  end

  test "from address uses location sender_from_address when present" do
    @location.stubs(:sender_from_address).returns("billing@cowork-tahoe.com")
    mail = UserMailer.membership_cancellation_email(@user, @operator, @subscription, @location, immediate: false)
    assert_includes mail.from, "billing@cowork-tahoe.com"
  end

  test "scheduled cancellation says it will not renew and never uses auto-renew wording" do
    @subscription.stubs(:current_period_end).returns(Time.utc(2026, 5, 28))
    mail = UserMailer.membership_cancellation_email(@user, @operator, @subscription, @location, immediate: false)
    body = mail.body.to_s

    assert_match(/will not renew/i, body)
    # The auto-renew reminder phrasing must never appear in a cancellation email.
    refute_match(/will renew on/i, body)
  end

  test "scheduled cancellation shows the access-until date when present" do
    @subscription.stubs(:current_period_end).returns(Time.utc(2026, 5, 28))
    mail = UserMailer.membership_cancellation_email(@user, @operator, @subscription, @location, immediate: false)
    assert_match "May 28, 2026", mail.body.to_s
  end

  test "scheduled cancellation does not crash and omits the date when no period end" do
    @subscription.stubs(:current_period_end).returns(nil)
    mail = UserMailer.membership_cancellation_email(@user, @operator, @subscription, @location, immediate: false)
    assert_match(/will not renew/i, mail.body.to_s)
  end

  test "immediate cancellation says it is canceled effective today" do
    mail = UserMailer.membership_cancellation_email(@user, @operator, @subscription, @location, immediate: true)
    body = mail.body.to_s
    assert_match(/effective today/i, body)
    refute_match(/will renew on/i, body)
  end

  test "subject differs for immediate vs scheduled cancellation" do
    immediate = UserMailer.membership_cancellation_email(@user, @operator, @subscription, @location, immediate: true)
    scheduled = UserMailer.membership_cancellation_email(@user, @operator, @subscription, @location, immediate: false)
    assert_no_match(/renew/i, immediate.subject)
    assert_no_match(/renew soon/i, scheduled.subject)
    refute_equal immediate.subject, scheduled.subject
  end
end
