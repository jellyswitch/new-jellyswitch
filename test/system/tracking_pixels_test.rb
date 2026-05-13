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

  test "admin setting tracking pixels" do
    user = users(:cowork_tahoe_admin)
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

  test "manager cannot set tracking pixels" do
    user = users(:cowork_tahoe_general_manager)
    log_in(user)

    operator = operators(:cowork_tahoe)
    location = operator.locations.first

    visit edit_location_path(location)

    assert_no_text "Tracking Pixels"
  end

  test "tracking pixels appears after user does a transaction" do
    StripeMock.start

    @user = users(:cowork_tahoe_non_member)
    setup_stripe_no_subscription

    log_in(@user)
    operator = operators(:cowork_tahoe)
    tracking_pixel = create :tracking_pixel, operator: operator, location: operator.locations.first, script: "<script>console.log('UA-12345678-1');</script>", position: :body
    visit home_path

    # assert the tracking pixel is not present
    assert !page.html.include?("UA-12345678-1")

    assert_text "Please select an option below."

    click_on "Buy a day pass"
    click_on "Select Standard Day Pass"

    assert_text "$200"

    click_on "Confirm and purchase"

    assert_text "Building Access"

    # assert the tracking pixel is present
    assert page.html.include?("UA-12345678-1")

    StripeMock.stop
  end
end
