require 'test_helper'

class RedirectorTest < ActiveSupport::TestCase
  setup do

  end

  teardown do

  end

  test 'it returns nil if location is absent' do
    operator = operators(:cowork_tahoe)
    user = users(:cowork_tahoe_member)

    redirect_path = Redirector.new(user: user, operator: operator, location: nil).landing
    assert_nil redirect_path
  end

  test 'it redirects to feed_items_path if user is admin' do

  end
end

#  Usage:
# module LandingHelper
#   def landing_redirect
#     if logged_in?
#       Redirector.new(user: current_user, operator: current_tenant, location: current_location).landing
#     else
#       nil
#     end
#   end
# end