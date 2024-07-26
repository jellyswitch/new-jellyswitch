require "application_system_test_case"
require "test_helper"

class DeleteOfficeTest < ApplicationSystemTestCase
  setup do
    @admin = create(:user, role: User::ADMIN)
    @superadmin = create(:user, role: User::SUPERADMIN)

    @door = create(:door)
    Door.reindex
  end

  test "admin should be able to delete a door" do
    log_in(@superadmin)

    visit edit_door_path(@door)

    click_on "Delete this door"

    within "#delete-door-modal" do
      assert_text "Warning: This action cannot be undone. Deleting this door will permanently remove:"
      assert_text "All door information (name, Kisi information, etc.)"
      assert_text "All access log history data"

      click_on "Confirm"
    end

    wait_for_turbo
    assert_match doors_path, current_path
    assert_text "#{@door.name} deleted."
    assert_nil Door.find_by(id: @door.id)
  end

  test "normal should not be able to delete a door" do
    log_in(@admin)

    visit edit_door_path(@door)

    assert_no_text "Delete this door"
  end
end
