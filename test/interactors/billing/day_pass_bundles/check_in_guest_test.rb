require "test_helper"

class Billing::DayPassBundles::CheckInGuestTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
  end

  def make_bundle(remaining: 5)
    dpt = DayPassType.create!(operator: @operator, location: @location, name: "Pack",
                              amount_in_cents: 20000, quantity: 5, available: true, visible: true)
    DayPassBundle.create!(user: @member, operator: @operator, location: @location, day_pass_type: dpt,
                          quantity_purchased: 5, passes_remaining: remaining, purchased_at: Time.current)
  end

  # Regression: burn_locked! used to end on enqueue_lifecycle_emails, so burn!
  # returned a job handle/nil and context.redemption was never the redemption row.
  test "burns a pass and exposes the created redemption on the context" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 5)

      result = Billing::DayPassBundles::CheckInGuest.call(
        bundle: bundle, performed_by: @member, guest_name: "Ada Lovelace")

      assert result.success?
      assert_instance_of DayPassBundleRedemption, result.redemption
      assert result.redemption.persisted?
      assert_equal bundle, result.redemption.day_pass_bundle
      assert_equal "guest", result.redemption.kind
      assert_equal "Ada Lovelace", result.redemption.guest_name
      assert_equal 4, bundle.reload.passes_remaining
    end
  end

  test "fails cleanly when the bundle is empty" do
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
      bundle = make_bundle(remaining: 0)

      result = Billing::DayPassBundles::CheckInGuest.call(
        bundle: bundle, performed_by: @member, guest_name: "Ada Lovelace")

      assert_not result.success?
      assert_equal "No passes remaining in this bundle.", result.message
      assert_equal 0, bundle.reload.passes_remaining
    end
  end
end
