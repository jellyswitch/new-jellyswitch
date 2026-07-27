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

  test "commitment cancellation states billing continues through the boundary date" do
    mail = UserMailer.membership_cancellation_email(
      @user, @operator, @subscription, @location,
      immediate: false, commitment_ends_on: Time.utc(2026, 9, 26)
    )
    body = mail.body.to_s

    assert_match "September 26, 2026", body
    assert_match(/commitment through/i, body)
    assert_match(/will end on/i, body)
    # The standard scheduled-cancel promise would be FALSE here — the member
    # keeps being billed until the commitment boundary.
    refute_match(/won't be billed for it again/i, body)
    refute_match(/will not renew/i, body)
  end

  test "commitment cancellation never reads Stripe for the period end" do
    @subscription.expects(:current_period_end).never
    mail = UserMailer.membership_cancellation_email(
      @user, @operator, @subscription, @location,
      immediate: false, commitment_ends_on: Time.utc(2026, 9, 26)
    )
    assert_match(/you won't be billed after that/i, mail.body.to_s)
  end

  test "commitment cancellation uses the scheduled subject" do
    commitment = UserMailer.membership_cancellation_email(
      @user, @operator, @subscription, @location,
      immediate: false, commitment_ends_on: Time.utc(2026, 9, 26)
    )
    scheduled = UserMailer.membership_cancellation_email(@user, @operator, @subscription, @location, immediate: false)
    assert_equal scheduled.subject, commitment.subject
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
