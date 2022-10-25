require 'test_helper'

class BillableFactoryTest < ActiveSupport::TestCase
  # Subscriptions

  test 'for memberships, it returns an individual when they are not a member of an organization' do
    users(:cowork_tahoe_member).update(organization_id: nil)

    assert BillableFactory.for(subscriptions(:cowork_tahoe_subscription)).billable == users(:cowork_tahoe_member)    
  end

  test 'for memberships, it returns an individual correctly even when that member is part of an organization but not set to bill it' do
    assert BillableFactory.for(subscriptions(:cowork_tahoe_subscription)).billable == users(:cowork_tahoe_member)
  end

  test 'for memberships, it returns an organization billing contact correctly' do
    users(:cowork_tahoe_member).update(bill_to_organization: true)

    assert BillableFactory.for(subscriptions(:cowork_tahoe_subscription)).billable == users(:cowork_tahoe_admin)
  end

  # Office Leases

  test 'for office leases, it returns an organizations billing contact' do
    assert BillableFactory.for(office_leases(:office_23b_lease).subscription).billable == users(:cowork_tahoe_admin) # billing contact for the organization
  end

  test 'for office leases, it returns an organization for an org without a billing contact' do
    organizations(:sierra_nevada_organization).update(billing_contact_id: nil)
    assert BillableFactory.for(office_leases(:office_23b_lease).subscription).billable == organizations(:sierra_nevada_organization)
  end

  # Day Passes

  test 'for day passes, it returns an individual when they are not a member of an organization' do
    users(:cowork_tahoe_member).update(organization_id: nil)

    assert BillableFactory.for(day_passes(:cowork_tahoe_day_pass)).billable == users(:cowork_tahoe_member)    
  end

  test 'for day passes, it returns an individual correctly even when that member is part of an organization but not set to bill it' do
    assert BillableFactory.for(day_passes(:cowork_tahoe_day_pass)).billable == users(:cowork_tahoe_member)
  end

  test 'for day passes, it returns an organization billing contact correctly' do
    users(:cowork_tahoe_member).update(bill_to_organization: true)

    assert BillableFactory.for(day_passes(:cowork_tahoe_day_pass)).billable == users(:cowork_tahoe_admin)
  end
end