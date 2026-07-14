require "test_helper"

class OrganizationTest < ActiveSupport::TestCase
  test "search_data tolerates an org with no owner" do
    # The OfficeRnD member importer (and any admin flow that skips the optional
    # owner) creates ownerless orgs; searchkick calls search_data at commit time,
    # so a nil owner must not raise.
    org = Organization.create!(name: "Ownerless LLC", operator: operators(:cowork_tahoe),
                               location_id: locations(:cowork_tahoe_location).id)
    data = org.search_data
    assert_nil data[:owner]
    assert_equal "Ownerless LLC", data[:name]
  end

  test "search_data includes the owner name when present" do
    data = organizations(:sierra_nevada_organization).search_data
    assert_equal users(:cowork_tahoe_admin).name, data[:owner]
  end
end
