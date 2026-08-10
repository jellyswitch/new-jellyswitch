require "test_helper"

# Admin "Burn a pass": spend one bundle pass with no date attached (e.g. an
# entry the old door system let through without a burn). Must decrement the
# pack and write an admin_burn ledger row WITHOUT minting a DayPass — a burn
# here must never grant door access or reservation coverage.
class Operator::DayPassBundleBurnsControllerTest < ActionDispatch::IntegrationTest
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
                                      day_pass_type: dpt, quantity_purchased: 5, passes_remaining: 2,
                                      purchased_at: Time.current)
    end
  end

  test "burn spends one pass, logs admin_burn, and mints no DayPass" do
    assert_no_difference -> { DayPass.count } do
      post user_day_pass_bundle_burns_path(@member),
        params: { day_pass_bundle_id: @bundle.id, reason: "old-system entry" }, env: default_env
    end

    assert_response :redirect
    assert_equal 1, @bundle.reload.passes_remaining

    redemption = @bundle.redemptions.order(:id).last
    assert_equal "admin_burn", redemption.kind
    assert_nil redemption.day_pass_id
    assert_equal @admin.id, redemption.performed_by_id
    assert_equal "old-system entry", redemption.guest_name
  end

  test "burning an empty pack alerts instead of crashing" do
    @bundle.update!(passes_remaining: 0)

    post user_day_pass_bundle_burns_path(@member),
      params: { day_pass_bundle_id: @bundle.id }, env: default_env

    assert_response :redirect
    assert_equal 0, @bundle.reload.passes_remaining
    assert_match(/No passes left/, flash[:alert])
  end

  test "non-staff cannot burn a pass" do
    delete logout_path, env: default_env
    log_in users(:cowork_tahoe_member)

    post user_day_pass_bundle_burns_path(@member),
      params: { day_pass_bundle_id: @bundle.id }, env: default_env

    assert_equal 2, @bundle.reload.passes_remaining,
      "a member must not be able to burn another member's pass"
  end
end
