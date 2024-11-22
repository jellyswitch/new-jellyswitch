require 'application_system_test_case'

class CustomizationsTest < ApplicationSystemTestCase
  test "superadmin viewing customizations" do
    user = users(:cowork_tahoe_admin)
    user.update role: User::SUPERADMIN
    log_in(user)

    operator = operators(:cowork_tahoe)
    location = operator.locations.first
    other_location = create(:location, operator: operator, name: "Other Location")

    visit customization_path

    click_on "Customize Jellyswitch"

    assert page.has_link?("Manage #{location.name}")
    assert page.has_link?("Manage #{other_location.name}")
    assert page.has_link?("Customize Jellyswitch")
  end

  test "admin viewing customizations" do
    user = users(:cowork_tahoe_admin)
    log_in(user)

    operator = operators(:cowork_tahoe)
    location = operator.locations.first
    other_location = create(:location, operator: operator, name: "Other Location")

    visit customization_path

    click_on "Customize Jellyswitch"

    assert page.has_link?("Manage #{location.name}")
    assert !page.has_link?("Manage #{other_location.name}")
    assert !page.has_link?("Customize Jellyswitch")
  end

  test "general manager viewing customizations" do
    user = users(:cowork_tahoe_general_manager)
    log_in(user)

    operator = operators(:cowork_tahoe)
    location = operator.locations.first
    other_location = create(:location, operator: operator, name: "Other Location")

    visit customization_path

    click_on "Customize Jellyswitch"

    assert page.has_link?("Manage #{location.name}")
    assert !page.has_link?("Manage #{other_location.name}")
    assert !page.has_link?("Customize Jellyswitch")
  end

  test "community manager viewing customizations" do
    user = users(:cowork_tahoe_community_manager)
    log_in(user)

    operator = operators(:cowork_tahoe)
    location = operator.locations.first
    other_location = create(:location, operator: operator, name: "Other Location")

    visit customization_path

    assert_text "Whoops! That's not allowed."
  end
end