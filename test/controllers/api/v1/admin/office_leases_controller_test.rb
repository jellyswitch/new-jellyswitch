require "test_helper"

# POST /api/v1/admin/office_leases — the mobile admin "Create Lease" form.
# Until now this action built a bare OfficeLease with no subscription, so it
# could never save. It now runs the same CreateOfficeLease pipeline the web
# form uses.
class Api::V1::Admin::OfficeLeasesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin    = users(:cowork_tahoe_admin)
    @operator = operators(:cowork_tahoe)
    @token = JWT.encode(
      { user_id: @admin.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )

    # The web form only offers organizations with billing set up (a Stripe
    # customer or out_of_band); the mobile picker mirrors that filter.
    organizations(:sierra_nevada_organization).update!(stripe_customer_id: "cus_test_sierra")

    stub_request(:post, "https://api.stripe.com/v1/plans")
      .to_return(status: 200, body: { id: "plan_xxx" }.to_json, headers: {})
    stub_request(:post, "https://api.stripe.com/v1/subscriptions")
      .to_return(status: 200, body: { id: "sub_xxx" }.to_json, headers: {})
  end

  teardown do
    WebMock.reset!
  end

  def headers
    {
      "Authorization"        => "Bearer #{@token}",
      "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type"         => "application/json",
    }
  end

  test "creates an organization lease with a subscription and plan" do
    start_on = Date.current + 10.days

    before = OfficeLease.count
    post "/api/v1/admin/office_leases", headers: headers, params: {
      office_lease: {
        office_id: offices(:free_office).id,
        organization_id: organizations(:sierra_nevada_organization).id,
        amount_in_cents: 70000,
        start_date: start_on.to_s,
        end_date: (start_on + 1.year).to_s,
      },
    }.to_json

    assert_response :created, response.body
    assert_equal before + 1, OfficeLease.count
    lease = OfficeLease.order(:id).last
    assert_equal offices(:free_office), lease.office
    assert_equal organizations(:sierra_nevada_organization), lease.organization
    assert_equal start_on, lease.start_date
    assert_equal start_on, lease.initial_invoice_date
    assert_equal 70000, lease.subscription.plan.amount_in_cents
    assert_equal "lease", lease.subscription.plan.plan_type
    assert_equal locations(:cowork_tahoe_location), lease.location

    body = JSON.parse(response.body)
    assert_equal "Free Office", body["office_name"]
    assert_equal "upcoming", body["status"]
  end

  test "creates an individual lease and defaults dates" do
    assert_difference("OfficeLease.count", 1) do
      post "/api/v1/admin/office_leases", headers: headers, params: {
        office_lease: {
          office_id: offices(:free_office).id,
          user_id: users(:cowork_tahoe_member).id,
          amount_in_cents: 50000,
        },
      }.to_json
    end

    assert_response :created
    lease = OfficeLease.order(:id).last
    assert_equal users(:cowork_tahoe_member), lease.user
    assert_nil lease.organization
    assert_equal Date.current, lease.start_date
    assert_equal Date.current + 1.year, lease.end_date
    assert_equal Date.current, lease.initial_invoice_date
  end

  test "rejects a lease that overlaps the office's current lease with the model's message" do
    assert_no_difference("OfficeLease.count") do
      post "/api/v1/admin/office_leases", headers: headers, params: {
        office_lease: {
          office_id: offices(:office_23b).id,
          organization_id: organizations(:sierra_nevada_organization).id,
          amount_in_cents: 70000,
        },
      }.to_json
    end

    assert_response :unprocessable_entity
    assert_match(/already has a lease/, JSON.parse(response.body)["error"])
  end

  test "rejects a lease with no lessee" do
    assert_no_difference("OfficeLease.count") do
      post "/api/v1/admin/office_leases", headers: headers, params: {
        office_lease: { office_id: offices(:free_office).id, amount_in_cents: 70000 },
      }.to_json
    end

    assert_response :unprocessable_entity
  end
end
