require "test_helper"

class DayPassPolicyTest < PolicyAssertions::Test

  setup do
    @admin = UserContext.new(users(:cowork_tahoe_admin), operators(:cowork_tahoe), locations(:cowork_tahoe))
    @member = users(:cowork_tahoe_member)
    @community_manager = UserContext.new(users(:cowork_tahoe_community_manager), operators(:cowork_tahoe), locations(:cowork_tahoe))
    @general_manager = UserContext.new(users(:cowork_tahoe_general_manager), operators(:cowork_tahoe), locations(:cowork_tahoe))
  end

  def test_create
    assert_permit @admin, DayPass
  end
end