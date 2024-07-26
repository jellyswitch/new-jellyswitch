require "application_system_test_case"
require "test_helper"

class DeleteGroupTest < ApplicationSystemTestCase
  setup do
    @user = create(:user)
    @superadmin = create(:user, role: User::SUPERADMIN)

    @group_no_lease = create(:organization)

    @group_with_active_lease = create(:organization)
    @group_with_active_lease.office_leases << create(:office_lease, start_date: 1.month.ago, end_date: 1.month.from_now)

    @group_with_active_subscription = create(:organization)
    @group_with_active_subscription.subscriptions << create(:subscription, active: true)

    @group_with_past_lease = create(:organization)
    @group_with_past_lease.office_leases << create(:office_lease, start_date: 1.month.ago, end_date: 1.day.ago)

    Organization.reindex
  end

  test "superadmin should be able to delete a group with no active lease" do
    log_in(@superadmin)

    visit organization_path(@group_no_lease)

    click_on "Delete this group"

    within "#delete-group-modal" do
      assert_text "Warning: This action cannot be undone. Deleting this group will permanently remove:"
      assert_text "All group information (name, stripe information, website, etc.)"
      assert_text "All associated office lease and invoice history data"

      click_on "Confirm"
    end

    wait_for_turbo
    assert_match organizations_path, current_path
    assert_text "#{@group_no_lease.name} deleted."
    assert_nil Organization.find_by(id: @group_no_lease.id)
  end

  test "superadmin should not be able to delete a group with an active lease" do
    log_in(@superadmin)

    visit organization_path(@group_with_active_lease)

    click_on "Delete this group"

    within "#delete-group-modal" do
      assert_text "Note: This group cannot be deleted because it has at least one active office lease or subscription."

      assert_selector "button[disabled]", text: "Confirm"
    end
  end

  test "superadmin should not be able to delete a group with an active subscription" do
    log_in(@superadmin)

    visit organization_path(@group_with_active_subscription)

    click_on "Delete this group"

    within "#delete-group-modal" do
      assert_text "Note: This group cannot be deleted because it has at least one active office lease or subscription."

      assert_selector "button[disabled]", text: "Confirm"
    end
  end

  test "superadmin should be able to delete a group with an past lease" do
    log_in(@superadmin)

    visit organization_path(@group_with_past_lease)

    click_on "Delete this group"

    within "#delete-group-modal" do
      click_on "Confirm"
    end

    wait_for_turbo
    assert_match organizations_path, current_path
    assert_text "#{@group_with_past_lease.name} deleted."
    assert_nil Organization.find_by(id: @group_with_past_lease.id)
  end

  test "user should not be able to delete a group" do
    log_in(@user)

    visit organization_path(@group_with_active_lease)

    assert_no_text "Delete this group"
  end
end
