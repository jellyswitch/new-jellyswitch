require "test_helper"

# Coverage for POST /api/v1/admin/reports/member_csv.
#
# MemberCsvExportJob#perform takes three arguments
# (operator_id, location_id, user_email). This endpoint previously
# enqueued it with only two — (current_tenant.id, current_api_user.id) —
# which raised "ArgumentError: wrong number of arguments (given 2,
# expected 3)" at perform time, so the CSV was never emailed even though
# the endpoint reported success. This test locks in the correct arity and
# arguments.
class Api::V1::Admin::ReportsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admin    = users(:cowork_tahoe_admin)
    @operator = operators(:cowork_tahoe)

    @token = JWT.encode(
      { user_id: @admin.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
  end

  def headers
    {
      "Authorization"        => "Bearer #{@token}",
      "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type"         => "application/json",
    }
  end

  test "member_csv enqueues export with operator id, nil location, and requester email" do
    assert_enqueued_with(
      job: MemberCsvExportJob,
      args: [@operator.id, nil, @admin.email],
    ) do
      post "/api/v1/admin/reports/member_csv", headers: headers
    end

    assert_response :success
  end
end
