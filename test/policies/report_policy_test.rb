require "test_helper"

class ReportPolicyTest < PolicyAssertions::Test

  setup do
    setup_initial_user_fixtures
  end

  def test_index
    assert_not_permitted @member, :report
    assert_permit @admin, :report
    assert_not_permitted @community_manager, :report
    assert_permit @general_manager, :report
  end

  def test_member_csv
    assert_not_permitted @member, :report
    assert_permit @admin, :report
    assert_not_permitted @community_manager, :report
    assert_permit @general_manager, :report
  end

  def test_active_lease_members
    assert_not_permitted @member, :report
    assert_permit @admin, :report
    assert_not_permitted @community_manager, :report
    assert_permit @general_manager, :report
  end

  def test_active_members
    assert_not_permitted @member, :report
    assert_permit @admin, :report
    assert_not_permitted @community_manager, :report
    assert_permit @general_manager, :report
  end

  def test_active_leases
    assert_not_permitted @member, :report
    assert_permit @admin, :report
    assert_not_permitted @community_manager, :report
    assert_permit @general_manager, :report
  end

  def test_last_30_day_passes
    assert_not_permitted @member, :report
    assert_permit @admin, :report
    assert_not_permitted @community_manager, :report
    assert_permit @general_manager, :report
  end

  def test_total_members
    assert_not_permitted @member, :report
    assert_permit @admin, :report
    assert_not_permitted @community_manager, :report
    assert_permit @general_manager, :report
  end

  def test_membership_breakdown
    assert_not_permitted @member, :report
    assert_permit @admin, :report
    assert_not_permitted @community_manager, :report
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
    assert_not_permitted @community_manager, :report
    assert_permit @general_manager, :report
  end

  def test_monetization
    assert_not_permitted @member, :report
    assert_permit @admin, :report
    assert_not_permitted @community_manager, :report
    assert_permit @general_manager, :report
  end
end