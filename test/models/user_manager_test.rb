require 'test_helper'

class UserManagerTest < ActiveSupport::TestCase
  test 'it scrubs personally identifiable info from the user record' do
    @user = users(:cowork_tahoe_member)
    @old_user = @user.dup

    UserManager.new(user: @user).ready
    @user.reload

    assert @user.name != @old_user.name
    assert @user.email != @old_user.email


    [:bio, :linkedin, :twitter, :website, :phone, :stripe_customer_id, :organization_id].map do |attr|
      assert @user.send(attr).blank?
    end
  end

  test 'it removes all future reservations' do
    
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