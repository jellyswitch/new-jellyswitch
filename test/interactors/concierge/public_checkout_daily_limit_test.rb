require "test_helper"

# Concierge::PublicCheckout is the anonymous widget purchase path (reached via
# Embed::ConciergeController#purchase with no login) — the most public entry
# point in the app — so it must respect DayPassType#daily_limit just like the
# four logged-in member self-serve paths.
# Spec: docs/superpowers/specs/2026-07-12-day-pass-daily-limit-design.md
class Concierge::PublicCheckoutDailyLimitTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
  end

  test "purchase is blocked when the day is at the type's limit, before any payment attempt" do
    day_pass_type = nil
    result = nil

    ActsAsTenant.with_tenant(@operator) do
      day_pass_type = DayPassType.create!(operator: @operator, location: @location, name: "Day Office",
                                          amount_in_cents: 2_500, quantity: 1, available: true, visible: true,
                                          daily_limit: 1)
      other = create(:user, operator: @operator, original_location: @location, current_location: @location)
      day = Date.current + 3
      DayPass.create!(user: other, billable: other, operator: @operator, location: @location,
                      day_pass_type: day_pass_type, day: day, imported: true)

      assert_no_difference -> { DayPass.count } do
        # If the gate didn't fire first, this stub would blow up the test —
        # positive proof the purchase never reaches the payment boundary.
        Billing::DayPasses::UpdatePaymentAndCreateDayPass.stub :call, ->(*) {
          flunk "payment must not be attempted when the day is already at its daily limit"
        } do
          result = Concierge::PublicCheckout.call(
            operator: @operator, location: @location, day_pass_type: day_pass_type, day: day,
            email: "widget.visitor@example.com", name: "Widget Visitor", password: "sup3rsecret",
            phone: "555-0100", terms_accepted: "1", token: "tok_visa",
          )
        end
      end
    end

    assert result.failure?
    assert_includes result.message, "fully booked"
  end
end
