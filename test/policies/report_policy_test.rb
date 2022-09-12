require "test_helper"

class ReportPolicyTest < PolicyAssertions::Test

  setup do
    @admin = users(:cowork_tahoe_admin)
    @member = users(:cowork_tahoe_member)
    @community_manager = users(:cowork_tahoe_community_manager)
    @general_manager = users(:cowork_tahoe_general_manager)
  end

  def test_index
    assert_not_permitted @member, :report
    assert_permit @admin, :report
    assert_permit @community_manager, :report
    assert_permit @general_manager, :report
  end

  def test_member_csv
    assert_not_permitted @member, :report
    assert_permit @admin, :report
    assert_permit @community_manager, :report
    assert_permit @general_manager, :report
  end

  def test_active_lease_members
    assert_not_permitted @member, :report
    assert_permit @admin, :report
    assert_permit @community_manager, :report
    assert_permit @general_manager, :report
  end

  def test_active_members
    assert_not_permitted @member, :report
    assert_permit @admin, :report
    assert_permit @community_manager, :report
    assert_permit @general_manager, :report
  end

  def test_active_leases
    assert_not_permitted @member, :report
    assert_permit @admin, :report
    assert_permit @community_manager, :report
    assert_permit @general_manager, :report
  end

  def test_last_30_day_passes
    assert_not_permitted @member, :report
    assert_permit @admin, :report
    assert_permit @community_manager, :report
    assert_permit @general_manager, :report
  end

  def test_total_members
    assert_not_permitted @member, :report
    assert_permit @admin, :report
    assert_permit @community_manager, :report
    assert_permit @general_manager, :report
  end

  def test_membership_breakdown
    assert_not_permitted @member, :report
    assert_permit @admin, :report
    assert_permit @community_manager, :report
    assert_permit @general_manager, :report
  end

  def test_revenue
    assert_not_permitted @member, :report
    assert_permit @admin, :report
    assert_not_permitted @community_manager, :report
    assert_permit @general_manager, :report
  end

  def test_checkins
    assert_not_permitted @member, :report
    assert_permit @admin, :report
    assert_permit @community_manager, :report
    assert_permit @general_manager, :report
  end

  def test_monetization
    assert_not_permitted @member, :report
    assert_permit @admin, :report
    assert_permit @community_manager, :report
    assert_permit @general_manager, :report
  end
end