require 'test_helper'

class OrganizationBillDeciderTest < ActiveSupport::TestCase
  test "it returns the organization's billing contact, if present" do
    assert_equal OrganizationBillDecider.new(organizations(:sierra_nevada_organization)).billable, users(:cowork_tahoe_admin)
  end

  test "if no billing contact is present, returns the organization" do
    organizations(:sierra_nevada_organization).update(billing_contact: nil)
    organizations(:sierra_nevada_organization).reload

    assert_equal OrganizationBillDecider.new(organizations(:sierra_nevada_organization)).billable, organizations(:sierra_nevada_organization)
  end
end