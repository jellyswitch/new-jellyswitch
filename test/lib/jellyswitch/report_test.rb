require "test_helper"

module Jellyswitch
  class ReportTest < ActiveSupport::TestCase
    setup do
      @operator = operators(:cowork_tahoe)
      @location = locations(:cowork_tahoe_location)
      @report   = Jellyswitch::Report.new(@operator, @location)
    end

    # An out-of-band member whose only membership basis was a group office
    # lease that has since ended is a *former* member, not a lapsed one, and
    # must not surface on the inactive-members re-engagement list.
    test "excludes out-of-band group members whose office lease has ended" do
      org = Organization.create!(
        name: "Expired Lease Co",
        operator: @operator,
        location: @location,
        out_of_band: false,
      )
      ended_subscription = Subscription.create!(
        plan: plans(:cowork_tahoe_office_lease_plan),
        subscribable: org,
        billable: org,
        active: false,
        start_date: 1.year.ago,
      )
      OfficeLease.create!(
        operator: @operator,
        location: @location,
        organization: org,
        office: offices(:office_23b),
        subscription: ended_subscription,
        start_date: 1.year.ago,
        end_date: 1.month.ago,
      )

      member = create_member(organization: org, out_of_band: true)

      assert_not_includes @report.inactive_members, member
    end

    # Control: an out-of-band member under an org whose lease is still active is
    # a genuine member; if they haven't visited recently they belong on the list.
    test "still flags out-of-band group members whose lease is active" do
      member = create_member(
        organization: organizations(:sierra_nevada_organization),
        out_of_band: true,
      )

      assert_includes @report.inactive_members, member
    end

    # Control: an out-of-band member with no organization at all is unaffected
    # by the group/lease filtering.
    test "still flags out-of-band members with no organization" do
      member = create_member(organization: nil, out_of_band: true)

      assert_includes @report.inactive_members, member
    end

    private

    def create_member(organization:, out_of_band:)
      suffix = SecureRandom.hex(4)
      User.create!(
        name: "Inactive Tester #{suffix}",
        email: "inactive-#{suffix}@example.com",
        password: "password123",
        admin_created: true,
        operator: @operator,
        original_location: @location,
        current_location: @location,
        organization: organization,
        out_of_band: out_of_band,
        approved: true,
        archived: false,
        role: User::UNASSIGNED,
        marketing_suppressed: false,
      )
    end
  end
end
