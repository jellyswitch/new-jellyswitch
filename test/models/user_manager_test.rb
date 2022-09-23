require 'test_helper'

class UserManagerTest < ActiveSupport::TestCase
  setup do
    @user = users(:cowork_tahoe_member)
    @old_user = @user.dup
  end

  test 'it scrubs personally identifiable info from the user record' do
    UserManager.new(user: @user).ready
    @user.reload

    assert @user.name != @old_user.name
    assert @user.email != @old_user.email


    [:bio, :linkedin, :twitter, :website, :phone, :stripe_customer_id, :organization_id].map do |attr|
      assert @user.send(attr).blank?
    end
  end

  test 'it removes all future reservations' do
    assert @user.reservations.future.count > 0
    UserManager.new(user: @user).ready
    @user.reload

    assert @user.reservations.future.count < 1
  end

  test 'it removes all active memberships' do
    
  end

  test 'it fails if the user is a group owner' do
    
  end

  test 'it creates a feed item for admins' do

  end

  test 'it archives the user' do

  end
end