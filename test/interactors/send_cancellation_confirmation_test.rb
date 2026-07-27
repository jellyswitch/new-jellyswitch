require "test_helper"

class SendCancellationConfirmationTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @subscription = subscriptions(:cowork_tahoe_subscription)
    @user = @subscription.subscribable
  end

  def call(**overrides)
    Billing::Subscription::SendCancellationConfirmation.call(
      { subscription: @subscription, user: @user, operator: @operator, location: @location }.merge(overrides)
    )
  end

  test "enqueues a scheduled-cancellation email when the subscription is still active" do
    @subscription.active = true
    mailer = mock("mail")
    mailer.expects(:deliver_later)
    UserMailer.expects(:membership_cancellation_email)
             .with(@user, @operator, @subscription, @location, immediate: false, commitment_ends_on: nil)
             .returns(mailer)

    assert call.success?
  end

  test "enqueues an immediate-cancellation email when the subscription is no longer active" do
    @subscription.active = false
    mailer = mock("mail")
    mailer.expects(:deliver_later)
    UserMailer.expects(:membership_cancellation_email)
             .with(@user, @operator, @subscription, @location, immediate: true, commitment_ends_on: nil)
             .returns(mailer)

    assert call.success?
  end

  test "falls back to the subscribable when no user is supplied" do
    mailer = mock("mail")
    mailer.stubs(:deliver_later)
    UserMailer.expects(:membership_cancellation_email)
             .with(@subscription.subscribable, @operator, @subscription, @location, immediate: false, commitment_ends_on: nil)
             .returns(mailer)

    assert call(user: nil).success?
  end

  test "passes commitment_ends_on through for commitment-scheduled cancels" do
    @subscription.active = true
    boundary = Time.utc(2026, 9, 26)
    mailer = mock("mail")
    mailer.expects(:deliver_later)
    UserMailer.expects(:membership_cancellation_email)
             .with(@user, @operator, @subscription, @location, immediate: false, commitment_ends_on: boundary)
             .returns(mailer)

    assert call(commitment_ends_on: boundary).success?
  end

  test "never rolls back the cancellation if email delivery raises" do
    UserMailer.stubs(:membership_cancellation_email).raises(StandardError.new("smtp down"))
    Honeybadger.stubs(:notify)

    assert call.success?, "a delivery error must not fail the cancellation"
  end

  test "is wired into the scheduled (cancel-at-period-end) organizer" do
    assert_includes SetSubscriptionForCancellation.organized,
                    Billing::Subscription::SendCancellationConfirmation
  end

  test "is wired into the immediate (cancel-now) organizer" do
    assert_includes Billing::Subscription::CancelSubscriptionNow.organized,
                    Billing::Subscription::SendCancellationConfirmation
  end
end
