require "test_helper"

# Coverage for LeaseRenewalReminderJob.
#
# Historically the job only processed auto_renew:true leases, so fixed-term
# (auto_renew:false) leases lapsed silently — nobody (operator or lessee) was
# warned before the end_date passed (e.g. Humane Society / Cowork Tahoe). The
# job now also warns on fixed-term leases entering the renewal-notice window,
# once per term, while leaving the auto-renew proposal flow intact.
class LeaseRenewalReminderJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @operator.update!(contact_email: "ops@coworktahoe.test")
    @member = users(:cowork_tahoe_member)
    ActionMailer::Base.deliveries.clear
  end

  # Individual (user-backed) lease so the lessee recipient is simply the user.
  def build_lease(auto_renew:, end_date:, start_date: 5.months.ago.to_date, notice_sent_at: nil)
    ActsAsTenant.with_tenant(@operator) do
      create(
        :office_lease,
        operator: @operator, location: @location,
        user: @member, organization: nil,
        auto_renew: auto_renew, start_date: start_date, end_date: end_date,
        renewal_notice_days: 60, renewal_notice_sent_at: notice_sent_at,
      )
    end
  end

  def recipients
    ActionMailer::Base.deliveries.flat_map(&:to)
  end

  test "fixed-term lease in the notice window warns operator + lessee, adds a feed card, and stamps" do
    lease = build_lease(auto_renew: false, end_date: 30.days.from_now.to_date)

    LeaseRenewalReminderJob.perform_now

    assert_includes recipients, @member.email, "lessee should be emailed"
    assert_includes recipients, @operator.contact_email, "operator should be emailed"
    assert FeedItem.where(operator: @operator)
                   .where("blob->>'type' = ?", "lease_expiring").exists?,
           "an admin feed card should be created"
    assert_not_nil lease.reload.renewal_notice_sent_at, "the lease should be stamped so it isn't re-notified"
  end

  test "a fixed-term lease already notified this term is not warned again" do
    build_lease(auto_renew: false, end_date: 30.days.from_now.to_date, notice_sent_at: 1.day.ago)

    LeaseRenewalReminderJob.perform_now

    assert_not_includes recipients, @member.email, "should not re-email a lease already notified this term"
  end

  test "a fixed-term lease outside the notice window is left alone" do
    lease = build_lease(auto_renew: false, end_date: 120.days.from_now.to_date)

    LeaseRenewalReminderJob.perform_now

    assert_not_includes recipients, @member.email
    assert_nil lease.reload.renewal_notice_sent_at
  end

  test "an auto-renew lease in the window still gets a renewal proposal (existing flow preserved)" do
    lease = build_lease(auto_renew: true, end_date: 30.days.from_now.to_date)
    lease.subscription.plan.update!(amount_in_cents: 50_000)

    assert_difference -> { LeaseRenewalRequest.where(office_lease: lease).count }, 1 do
      LeaseRenewalReminderJob.perform_now
    end
    # Auto-renew leases go down the proposal path, not the fixed-term expiry
    # path, so they are never stamped with renewal_notice_sent_at.
    assert_nil lease.reload.renewal_notice_sent_at
  end
end
