require "test_helper"

class SendRenewalRemindersJobTest < ActiveSupport::TestCase
  def visited_operators
    visited = []
    Subscription.stub(:renewal_reminder_candidates, -> { visited << ActsAsTenant.current_tenant; Subscription.none }) do
      SendRenewalRemindersJob.perform_now
    end
    visited
  end

  test "processes production operators" do
    assert_includes visited_operators, operators(:cowork_tahoe)
  end

  # Regression: closed (out-of-business) operators resolve to the TEST Stripe
  # key, so every renewal-candidate lookup on their live-mode subscriptions
  # raised "No such subscription… a similar object exists in live mode".
  test "skips closed operators" do
    operators(:cowork_tahoe).update_columns(billing_state: "closed")

    assert_not_includes visited_operators, operators(:cowork_tahoe)
  end
end
