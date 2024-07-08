require "application_system_test_case"

class ManageRoomsTest < ApplicationSystemTestCase
  NAME_INDEX = 0.freeze
  PRICE_INDEX = 1.freeze

  setup do
    @room = rooms(:small_meeting_room)
    @user = users(:cowork_tahoe_admin)

    log_in @user
  end

  teardown do
    StripeMock.stop
  end

  def name_input
    all("input")[NAME_INDEX]
  end

  def price_input
    all("input")[PRICE_INDEX]
  end

  test "should show room's amenities" do
    assert_current_path feed_items_path
    visit edit_room_path(@room)

    assert_text "Amenities"

    assert_selector "#amenities .nested-fields", count: @room.amenities.count

    @room.amenities.each_with_index do |amenity, index|
      within all("#amenities .nested-fields")[index] do
        assert_equal name_input.value, amenity.name
        assert_equal price_input.value, amenity.price.to_s
      end
    end
  end

  test "should able to add the room's amenities successfully" do
    @room.amenities.destroy_all
    assert_current_path feed_items_path
    visit edit_room_path(@room)

    assert_text "Amenities"

    within all("#amenities .nested-fields")[0] do
      name_input.set("Coffee")
      price_input.set("15.00")
    end

    click_on "+ Add More"

    assert_selector "#amenities .nested-fields", count: 2

    within all("#amenities .nested-fields")[1] do
      name_input.set("Tea")
    end

    click_on "Update room"

    assert_text "Room #{@room.name} has been updated."

    click_on "Edit Room"
    sleep 1

    within all("#amenities .nested-fields")[0] do
      assert_equal name_input.value, "Coffee"
      assert_equal price_input.value, "15.0"
    end

    within all("#amenities .nested-fields")[1] do
      assert_equal name_input.value, "Tea"
      assert_equal price_input.value, "0.0"
    end
  end

  test "should able to remove the room's amenities successfully" do
    @room.amenities.destroy_all
    Amenity.create(room: @room, name: "Coffee", price: 15.00)
    Amenity.create(room: @room, name: "AV", price: 20.00)

    assert_current_path feed_items_path
    visit edit_room_path(@room)

    assert_text "Amenities"

    assert_selector "#amenities .nested-fields", count: 2
    within all("#amenities .nested-fields").last do
      click_on "x"
    end

    click_on "Update room"
    assert_text "Room #{@room.name} has been updated."

    click_on "Edit Room"
    sleep 1

    assert_selector "#amenities .nested-fields", count: 1
  end
end
