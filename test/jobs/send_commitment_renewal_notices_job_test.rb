require "test_helper"

class SendCommitmentRenewalNoticesJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @operator = operators(:cowork_tahoe)
    @sub = subscriptions(:cowork_tahoe_subscription)
    @sub.plan.update!(interval: "monthly", commitment_interval: 6)
    @sub.update!(start_date: 2.months.ago.to_date, stripe_subscription_id: nil,
                 cancelling_at_end_of_billing_period: false)
    @boundary = @sub.commitment_term_end
    @days_out = (@boundary.to_date - Date.current).to_i
  end

  test "emails the member when the commitment boundary is exactly notice_days away" do
    @operator.update!(commitment_notice_days: @days_out)
    assert_emails 1 do
      SendCommitmentRenewalNoticesJob.perform_now
    end
  end

  test "does not email when the boundary is outside the notice window" do
    @operator.update!(commitment_notice_days: @days_out + 10)
    assert_emails 0 do
      SendCommitmentRenewalNoticesJob.perform_now
    end
  end

  test "does not email a member who already opted out (scheduled to cancel)" do
    @operator.update!(commitment_notice_days: @days_out)
    @sub.update!(cancelling_at_end_of_billing_period: true)
    assert_emails 0 do
      SendCommitmentRenewalNoticesJob.perform_now
    end
  end

  test "does not email for a plan with no commitment" do
    @operator.update!(commitment_notice_days: @days_out)
    @sub.plan.update!(commitment_interval: nil)
    assert_emails 0 do
      SendCommitmentRenewalNoticesJob.perform_now
    end
  end
end
