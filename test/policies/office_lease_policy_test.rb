require "test_helper"

class OfficeLeasePolicyTest < PolicyAssertions::Test
  setup do
    setup_initial_user_fixtures
  end

  def test_index
    assert_not_permitted @member, office_leases(:office_23b_lease)
    assert_permit @admin, office_leases(:office_23b_lease)
    assert_not_permitted @community_manager, office_leases(:office_23b_lease)
    assert_permit @general_manager, office_leases(:office_23b_lease)
    assert_permit @superadmin, office_leases(:office_23b_lease)
  end

  def test_show
    assert_not_permitted @member, office_leases(:office_23b_lease)
    assert_permit @admin, office_leases(:office_23b_lease)
    assert_not_permitted @community_manager, office_leases(:office_23b_lease)
    assert_permit @general_manager, office_leases(:office_23b_lease)
    assert_permit @superadmin, office_leases(:office_23b_lease)
  end

  def test_new
    assert_not_permitted @member, office_leases(:office_23b_lease)
    assert_permit @admin, office_leases(:office_23b_lease)
    assert_not_permitted @community_manager, office_leases(:office_23b_lease)
    assert_permit @general_manager, office_leases(:office_23b_lease)
    assert_permit @superadmin, office_leases(:office_23b_lease)
  end

  def test_create
    assert_not_permitted @member, office_leases(:office_23b_lease)
    assert_permit @admin, office_leases(:office_23b_lease)
    assert_not_permitted @community_manager, office_leases(:office_23b_lease)
    assert_permit @general_manager, office_leases(:office_23b_lease)
    assert_permit @superadmin, office_leases(:office_23b_lease)
  end

  def test_destroy
    assert_not_permitted @member, office_leases(:office_23b_lease)
    assert_permit @admin, office_leases(:office_23b_lease)
    assert_not_permitted @community_manager, office_leases(:office_23b_lease)
    assert_permit @general_manager, office_leases(:office_23b_lease)
    assert_permit @superadmin, office_leases(:office_23b_lease)
  end

  def test_renewal
    office_lease = create(:office_lease, start_date: Date.today, end_date: Date.today + 1.month)
    not_valid_lease = create(:office_lease, start_date: Date.today, end_date: Date.today + 3.months)

    assert_not_permitted @member, office_lease
    assert_permit @admin, office_lease
    assert_not_permitted @community_manager, office_lease
    assert_permit @general_manager, office_lease
    assert_permit @superadmin, office_lease

    assert_not_permitted @superadmin, not_valid_lease
  end

  def test_update_price
    office_lease = create(:office_lease, start_date: Date.today, end_date: Date.today + 1.month)
    office_lease.stub(:subscription_active?, true) do
      assert_not_permitted @member, office_lease, :update_price?
      assert_permit @admin, office_lease, :update_price?
      assert_not_permitted @community_manager, office_lease, :update_price?
      assert_permit @general_manager, office_lease, :update_price?
      assert_permit @superadmin, office_lease, :update_price?
    end

    not_valid_lease = create(:office_lease, start_date: Date.today - 3.months, end_date: Date.today - 2.months)
    assert_not_permitted @superadmin, not_valid_lease
  end

  def test_edit_price
    test_update_price
  end
end
