require "test_helper"

class Onboarding::UpdateOperatorNameTest < ActiveSupport::TestCase
  test "uses the chosen subdomain when provided" do
    user = users(:cowork_tahoe_admin)
    result = Onboarding::UpdateOperatorName.call(user: user, operator_name: "Tahoe Longhouse", subdomain: "tahoelonghouse")
    assert result.success?, (result.respond_to?(:message) ? result.message : "interactor failed")
    assert_equal "tahoelonghouse", user.operator.reload.subdomain
  end

  test "falls back to the parameterized name when subdomain is blank" do
    user = users(:cowork_tahoe_admin)
    result = Onboarding::UpdateOperatorName.call(user: user, operator_name: "Brand New Space", subdomain: "")
    assert result.success?
    assert_equal "brand-new-space", user.operator.reload.subdomain
  end

  test "parameterizes a messy chosen subdomain" do
    user = users(:cowork_tahoe_admin)
    Onboarding::UpdateOperatorName.call(user: user, operator_name: "X", subdomain: "Tahoe Longhouse")
    assert_equal "tahoe-longhouse", user.operator.reload.subdomain
  end
end
