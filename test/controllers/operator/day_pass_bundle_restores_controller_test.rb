require "test_helper"

# Admin "Restore a pass": +1 on a member's bundle, capped at the pack size.
# The cap case must say so — previously the controller flashed "Restored a
# pass" even when restore! no-opped at quantity_purchased.
class Operator::DayPassBundleRestoresControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin    = users(:cowork_tahoe_admin)
    @operator = @admin.operator
    @location = locations(:cowork_tahoe_location)
    @admin.update!(current_location: @location)
    log_in @admin

    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      dpt = DayPassType.create!(operator: @operator, location: @location, name: "5-Pack",
                                amount_in_cents: 20000, quantity: 5, available: true, visible: true)
      @bundle = DayPassBundle.create!(user: @member, operator: @operator, location: @location,
                                      day_pass_type: dpt, quantity_purchased: 5, passes_remaining: 4,
                                      purchased_at: Time.current)
    end
  end

  test "restore adds a pass back with an admin_restore ledger row" do
    post user_day_pass_bundle_restores_path(@member),
      params: { day_pass_bundle_id: @bundle.id, reason: "burned by accident" }, env: default_env

    assert_response :redirect
    assert_equal 5, @bundle.reload.passes_remaining
    assert_equal "admin_restore", @bundle.redemptions.order(:id).last.kind
    assert_match(/Restored a pass/, flash[:notice])
  end

  test "restoring a full pack alerts instead of claiming success" do
    @bundle.update!(passes_remaining: 5)

    post user_day_pass_bundle_restores_path(@member),
      params: { day_pass_bundle_id: @bundle.id }, env: default_env

    assert_response :redirect
    assert_equal 5, @bundle.reload.passes_remaining
    assert_nil flash[:notice]
    assert_match(/already at 5 passes/, flash[:alert])
  end
end
