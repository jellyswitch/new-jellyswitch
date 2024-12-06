require 'test_helper'

class OfficeLeasesControllerTest < ActionDispatch::IntegrationTest
  setup do
    stub_request(:post, "https://api.stripe.com/v1/plans")
      .to_return(status: 200, body: {id: 'plan_xxx'}.to_json, headers: {})

    stub_request(:post, "https://api.stripe.com/v1/subscriptions")
      .to_return(status: 200, body: {id: 'sub_xxx'}.to_json, headers: {})
  end

  test "should cancel office lease now to operator" do
    @user = users(:cowork_tahoe_member)
    @office_lease_plan = office_leases(:office_23b_lease)
    log_in @user

    delete destroy_office_lease_now_path(@office_lease_plan), headers: { "HTTP_REFERER": "http://www.example.com/office_leases/#{@office_lease_plan.id}" }, env: default_env

    assert_redirected_to office_lease_path(@office_lease_plan)
  end

  # TODO: Fix unstable on github action. Passes locally
  # test "should create office lease" do
  #   log_in users(:cowork_tahoe_admin)

  #   OfficeLease.delete_all

  #   current_time = Time.current
  #   post office_leases_path, params: { office_lease: {
  #     organization_id: organizations(:sierra_nevada_organization).id,
  #     office_id: offices(:office_23b).id,
  #     "start_date(2i)" => current_time.month.to_s,
  #     "start_date(3i)" => current_time.day.to_s,
  #     "start_date(1i)" => current_time.year.to_s,
  #     "end_date(2i)" => current_time.month.to_s,
  #     "end_date(3i)" => current_time.day.to_s,
  #     "end_date(1i)" => (current_time.year + 1).to_s,
  #     "initial_invoice_date(2i)" => current_time.month.to_s,
  #     "initial_invoice_date(3i)" => current_time.day.to_s,
  #     "initial_invoice_date(1i)" => current_time.year.to_s,
  #     subscription_attributes: {
  #       plan_attributes: {
  #         name: "Office Lease Plan",
  #         plan_type: "lease",
  #         interval: "monthly",
  #         amount_in_cents: "32453463"
  #       }
  #     }
  #   }}, headers: { "HTTP_REFERER": "http://www.example.com/office_leases/new" }, env: default_env

  #   assert OfficeLease.last.organization_id == organizations(:sierra_nevada_organization).id
  #   assert OfficeLease.last.office_id == offices(:office_23b).id
  #   assert Plan.last.location == locations(:cowork_tahoe_location)
  # end
end