require 'test_helper'

class RedirectorTest < ActiveSupport::TestCase
  include Rails.application.routes.url_helpers

  # Landing Redirect

  test 'it returns nil if location is absent' do
    operator = operators(:cowork_tahoe)
    user = users(:cowork_tahoe_member)

    redirect_path = Redirector.new(user: user, operator: operator, location: nil).landing

    assert_nil redirect_path
  end

  test 'it takes admins to the feed' do
    operator = operators(:cowork_tahoe)
    user = users(:cowork_tahoe_admin)
    location = operator.locations.first

    redirect_path = Redirector.new(user: user, operator: operator, location: location).landing
    
    assert redirect_path == feed_items_path
  end

  test 'it takes community managers to the feed' do
    operator = operators(:cowork_tahoe)
    user = users(:cowork_tahoe_community_manager)
    location = operator.locations.first

    redirect_path = Redirector.new(user: user, operator: operator, location: location).landing
    
    assert redirect_path == feed_items_path
  end

  test 'it takes general managers to the feed' do
    operator = operators(:cowork_tahoe)
    user = users(:cowork_tahoe_general_manager)
    location = operator.locations.first

    redirect_path = Redirector.new(user: user, operator: operator, location: location).landing
    
    assert redirect_path == feed_items_path
  end
  
  test 'operator onboarding' do
    skip "No operators are currently not onboarded and we don't anticipate this going forward"
  end

  test 'it takes approved members to the dashboard' do
    operator = operators(:cowork_tahoe)
    user = users(:cowork_tahoe_member)
    location = operator.locations.first

    redirect_path = Redirector.new(user: user, operator: operator, location: location).landing
    
    assert redirect_path == home_path
  end

  test 'it takes members who need to check in to the check in page' do
    skip "No operators are currently requiring check-ins and we don't anticipate this going forward"
  end

  test 'it takes members who are not approved to the wait page' do
    operator = operators(:cowork_tahoe)
    user = users(:cowork_tahoe_member)
    user.update(approved: false)
    location = operator.locations.first

    redirect_path = Redirector.new(user: user, operator: operator, location: location).landing
    
    assert redirect_path == wait_path
  end

  test 'it takes non-members to the choose page' do
    operator = operators(:cowork_tahoe)
    user = users(:cowork_tahoe_non_member)
    location = operator.locations.first

    redirect_path = Redirector.new(user: user, operator: operator, location: location).landing
    
    assert redirect_path == choose_path
  end

  # Home Redirect
  # Todo
end