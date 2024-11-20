require 'application_system_test_case'

class TrackingPixelsTest < ApplicationSystemTestCase
  test "superadmin setting tracking pixels" do
    user = users(:cowork_tahoe_superadmin)
    log_in(user)

    operator = operators(:cowork_tahoe)
    location = operator.locations.first

    visit edit_location_path(location)

    assert_text "Tracking Pixels"

    click_on "Add Tracking Pixel"

    within ".pixel-fields-container" do
      fill_in "Name", with: "Google Analytics"
      fill_in "Pixel code", with: "UA-12345678-1"
      find('select.form-control').select('Body')
    end

    click_on "Update"

    visit edit_location_path(location)

    within ".pixel-fields-container" do
      assert_field "Name", with: "Google Analytics"
      assert_field "Pixel code", with: "UA-12345678-1"
      assert_equal "body", find('select.form-control').value
    end
  end
end
