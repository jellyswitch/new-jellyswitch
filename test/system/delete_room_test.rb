require "application_system_test_case"
require "test_helper"

class DeleteOfficeTest < ApplicationSystemTestCase
  setup do
    @user = create(:user)
    @superadmin = create(:user, role: User::SUPERADMIN)

    @room = create(:room)
  end

  test "superadmin should be able to delete a room" do
    log_in(@superadmin)

    visit edit_room_path(@room)

    click_on "Delete this room"

    within "#delete-room-modal" do
      assert_text "This action cannot be undone. Deleting this room will permanently remove:"
      assert_text "All room information (name, amenities, photo, etc.)"
      assert_text "All reservation history"

      click_on "Confirm"
    end

    wait_for_turbo
    assert_match rooms_path, current_path
    assert_text "#{@room.name} deleted."
    assert_nil Room.find_by(id: @room.id)
  end

  test "user should not be able to delete a room" do
    log_in(@user)

    visit room_path(@room)

    assert_no_text "Delete this room"
  end
end
