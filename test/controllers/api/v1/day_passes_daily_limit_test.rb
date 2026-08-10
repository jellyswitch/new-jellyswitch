require "test_helper"

# Member self-serve purchase respects DayPassType#daily_limit.
# Spec: docs/superpowers/specs/2026-07-12-day-pass-daily-limit-design.md
class Api::V1::DayPassesDailyLimitTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @member   = users(:cowork_tahoe_member)
    @type     = day_pass_type(:cowork_tahoe_day_pass_type)
    @day      = (Date.current + 2)
  end

  def headers(user = @member)
    token = JWT.encode(
      { user_id: user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain }
  end

  def fill_day(count)
    ActsAsTenant.with_tenant(@operator) do
      count.times do
        u = create(:user, operator: @operator, original_location: @location, current_location: @location)
        DayPass.create!(user: u, billable: u, operator: @operator, location: @location,
                        day_pass_type: @type, day: @day, imported: true)
      end
    end
  end

  test "purchase is blocked when the day is at the type's limit" do
    @type.update!(daily_limit: 2)
    fill_day(2)

    assert_no_difference -> { DayPass.count } do
      post "/api/v1/day_passes",
           params: { day_pass_type_id: @type.id, date: @day.iso8601 }, headers: headers
    end

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["error"], "fully booked"
  end

  test "purchase proceeds past the gate when under the limit" do
    @type.update!(daily_limit: 2)
    fill_day(1)

    # The interactor chain (Stripe invoice creation, charge) is a real
    # network integration with no stub anywhere else in this suite — every
    # existing test that reaches Billing::DayPasses::CreateDayPass stubs the
    # interactor call itself (see test/controllers/day_passes_controller_test.rb,
    # test/interactors/billing/reservations/buy_coverage_day_pass_test.rb). We
    # follow that convention here: the point of this test is only that the
    # daily-limit gate did not fire, not that a real charge succeeds or fails
    # a particular way. A "fully booked" error would mean the gate is
    # miscounting; anything else means the request cleared the gate and
    # reached the (stubbed) purchase interactor.
    canned_failure = Struct.new(:success?, :message, :outcome).new(false, "Payment failed.", nil)
    Billing::DayPasses::CreateDayPass.stub :call, canned_failure do
      post "/api/v1/day_passes",
           params: { day_pass_type_id: @type.id, date: @day.iso8601 }, headers: headers
    end

    refute_includes response.body, "fully booked"
    # Positive proof the request cleared the gate and reached the (stubbed)
    # billing boundary — without this the test could pass vacuously if auth,
    # routing, or an earlier guard broke.
    assert_includes response.body, "Payment failed."
  end

  test "no limit set means never blocked" do
    assert_nil @type.daily_limit
    fill_day(3)

    canned_failure = Struct.new(:success?, :message, :outcome).new(false, "Payment failed.", nil)
    Billing::DayPasses::CreateDayPass.stub :call, canned_failure do
      post "/api/v1/day_passes",
           params: { day_pass_type_id: @type.id, date: @day.iso8601 }, headers: headers
    end

    refute_includes response.body, "fully booked"
    # Positive proof the request cleared the gate and reached the (stubbed)
    # billing boundary — without this the test could pass vacuously if auth,
    # routing, or an earlier guard broke.
    assert_includes response.body, "Payment failed."
  end
end
