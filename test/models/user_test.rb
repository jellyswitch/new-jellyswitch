require 'test_helper'

class UserTest < ActiveSupport::TestCase
  setup do
    @location = locations(:cowork_tahoe_location)
  end

  test 'User#should_charge_for_reservation?(location) returns false if user is an admin (role)' do
    user = users(:cowork_tahoe_admin)

    assert user.should_charge_for_reservation?(@location) == false
  end

  test 'User#should_charge_for_reservation?(location) returns false if user is a superadmin (role)' do
    user = users(:cowork_tahoe_superadmin)
    
    assert user.should_charge_for_reservation?(@location) == false
  end

  test 'User#should_charge_for_reservation?(location) returns false if user is a general manager (role)' do
    user = users(:cowork_tahoe_general_manager)
    
    assert user.should_charge_for_reservation?(@location) == false
  end

  test 'User#should_charge_for_reservation?(location) returns true if user is a community manager (role)' do
    user = users(:cowork_tahoe_community_manager)
    
    assert user.should_charge_for_reservation?(@location) == true
  end

  test 'User#should_charge_for_reservation?(location) returns true if user is unassigned (role)' do
    user = users(:cowork_tahoe_member)
    
    assert user.should_charge_for_reservation?(@location) == true
  end
end