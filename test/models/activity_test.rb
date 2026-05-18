require 'test_helper'

class ActivityTest < ActiveSupport::TestCase
  test "tour_request is a valid Activity kind" do
    user = users(:cowork_tahoe_member)
    operator = user.operator
    activity = Activity.new(user: user, operator: operator, kind: :tour_request, occurred_at: Time.current, payload: {})
    assert activity.valid?, activity.errors.full_messages.inspect
  end
end
