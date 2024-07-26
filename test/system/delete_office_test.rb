require "application_system_test_case"
require "test_helper"

class DeleteOfficeTest < ApplicationSystemTestCase
  setup do
    @user = create(:user)
    @superadmin = create(:user, role: User::SUPERADMIN)

    @office_no_lease = create(:office)
    @office_with_active_lease = create(:office, :with_active_lease)

    @office_with_past_lease = create(:office)
    create(:office_lease, office: @office_with_past_lease, start_date: 1.month.ago, end_date: 1.day.ago)
  end

  test "superadmin should be able to delete an office with no active lease" do
    log_in(@superadmin)

    visit office_path(@office_no_lease)

    click_on "Delete this office"

    within "#delete-office-modal" do
      assert_text "This action cannot be undone. Deleting this office will permanently remove:"
      assert_text "All office information (name, description, capacity, etc.)"
      assert_text "All associated office lease history and data"

      click_on "Confirm"
    end

    wait_for_turbo
    assert_match offices_path, current_path
    assert_text "#{@office_no_lease.name} deleted."
    assert_nil Office.find_by(id: @office_no_lease.id)
  end

  test "superadmin should not be able to delete an office with an active lease" do
    log_in(@superadmin)

    visit office_path(@office_with_active_lease)

    click_on "Delete this office"

    within "#delete-office-modal" do
      assert_text "Note: This office cannot be deleted because it has an active lease."

      assert_selector "button[disabled]", text: "Confirm"
    end
  end

  test "superadmin should be able to delete an office with an past lease" do
    log_in(@superadmin)

    visit office_path(@office_with_past_lease)

    click_on "Delete this office"

    within "#delete-office-modal" do
      click_on "Confirm"
    end

    wait_for_turbo
    assert_match offices_path, current_path
    assert_text "#{@office_with_past_lease.name} deleted."
    assert_nil Office.find_by(id: @office_with_past_lease.id)
  end

  test "user should not be able to delete an office" do
    log_in(@user)

    visit office_path(@office_with_active_lease)

    assert_no_text "Delete this office"
  end
end
