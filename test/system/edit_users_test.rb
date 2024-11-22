require 'application_system_test_case'

class EditUsersTest < ApplicationSystemTestCase
  test "superadmin edit user" do
    log_in(users(:cowork_tahoe_superadmin))
    operator = operators(:cowork_tahoe)
    other_location = create(:location, operator: operator, name: 'Other Location')

    visit edit_user_path(users(:cowork_tahoe_member))

    assert page.has_select?('user_role', options: ['Superadmin', 'Admin', 'Community Manager', 'General Manager', 'Unassigned'])
    select('Admin', from: 'user_role')
    assert page.has_select?('user_managed_location_ids', with_options: [locations(:cowork_tahoe_location).name, other_location.name])
  end

  test "admin edit user" do
    log_in(users(:cowork_tahoe_admin))
    operator = operators(:cowork_tahoe)
    other_location = create(:location, operator: operator, name: 'Other Location')

    visit edit_user_path(users(:cowork_tahoe_member))

    assert page.has_select?('user_role', options: ['Admin', 'Community Manager', 'General Manager', 'Unassigned'])
    select('Admin', from: 'user_role')
    assert page.has_select?('user_managed_location_ids', options: [locations(:cowork_tahoe_location).name])
  end

  test "general manager edit user" do
    log_in(users(:cowork_tahoe_general_manager))
    operator = operators(:cowork_tahoe)
    other_location = create(:location, operator: operator, name: 'Other Location')

    visit edit_user_path(users(:cowork_tahoe_member))

    assert page.has_select?('user_role', options: ['Community Manager', 'General Manager', 'Unassigned'])
    select('Community Manager', from: 'user_role')
    assert page.has_select?('user_managed_location_ids', options: [locations(:cowork_tahoe_location).name])
  end

  test "community manager edit user" do
    log_in(users(:cowork_tahoe_community_manager))
    operator = operators(:cowork_tahoe)
    other_location = create(:location, operator: operator, name: 'Other Location')

    visit edit_user_path(users(:cowork_tahoe_member))

    assert page.has_no_select?('user_role')
    assert page.has_no_select?('user_managed_location_ids')
  end
end