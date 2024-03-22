require 'test_helper'

class RedirectorTest < ActiveSupport::TestCase
  include Rails.application.routes.url_helpers

  test 'it returns nil if location is absent' do
    operator = operators(:cowork_tahoe)
    user = users(:cowork_tahoe_member)

    redirect_path = Redirector.new(user: user, operator: operator, location: nil).landing

    assert_nil redirect_path
  end

  test 'it takes admins to feed_items_path' do
    operator = operators(:cowork_tahoe)
    user = users(:cowork_tahoe_admin)
    location = operator.locations.first

    redirect_path = Redirector.new(user: user, operator: operator, location: location).landing
    
    assert redirect_path == feed_items_path
  end
end