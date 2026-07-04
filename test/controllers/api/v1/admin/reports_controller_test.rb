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

  # The "Last Month" chip previously fed a trailing day count (~31 days ending
  # today) to every count metric, so it showed last month's revenue next to
  # this-month check-ins. All metrics must use the calendar month window.
  test "last_month period counts check-ins from the calendar month only" do
    location = locations(:cowork_tahoe_location)
    member = users(:cowork_tahoe_member)
    mid_last_month = Date.current.prev_month.beginning_of_month.in_time_zone.change(day: 15, hour: 10)
    Checkin.create!(
      user: member,
      billable: member,
      location: location,
      datetime_in: mid_last_month,
      datetime_out: mid_last_month + 2.hours,
    )
    # fixture checkin from today must NOT be counted for last_month

    get "/api/v1/admin/reports", params: { period: "last_month" }, headers: headers
    assert_response :success

    last_month = Date.current.prev_month
    window = last_month.beginning_of_month.beginning_of_day..last_month.end_of_month.end_of_day
    expected = Checkin.where(location: location, datetime_in: window).count
    assert_equal expected, response.parsed_body["checkin_count"]
  end

  # The monthly list previously summed operator-wide amount_paid by `date`,
  # disagreeing with both the dashboard tile and the web chart. It now goes
  # through Report#revenue_by_month (paid location invoices + lease checks).
  test "revenue endpoint returns cents matching Report#revenue_by_month" do
    get "/api/v1/admin/reports/revenue", params: { period: "12" }, headers: headers
    assert_response :success

    months = response.parsed_body["months"]
    assert_equal 12, months.length
    assert_equal months.map { |m| m["month"] }.sort, months.map { |m| m["month"] },
      "months must be in ascending order"

    report = Jellyswitch::Report.new(@operator, locations(:cowork_tahoe_location))
    expected = report.revenue_by_month(12).transform_values { |dollars| (dollars * 100).round }
    months.each do |m|
      month_date = Date.strptime(m["month"], "%Y-%m")
      assert_equal expected[month_date], m["amount"], "amount mismatch for #{m["month"]}"
    end
  end
end
