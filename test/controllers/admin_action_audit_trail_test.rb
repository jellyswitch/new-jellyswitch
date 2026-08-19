require "test_helper"

# Audit trail for account-state changes. Born from a five-day mystery:
# someone archived the Cowork Tahoe space host's account via the mobile
# admin app on 2026-08-14 and nothing recorded who. Every archive /
# unarchive / approve / unapprove — web or mobile API — now lands an
# `admin_action` Activity on the member's timeline naming the actor;
# self-service account deletion logs itself the same way.
class AdminActionAuditTrailTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @admin    = users(:cowork_tahoe_admin)
    ActsAsTenant.with_tenant(@operator) do
      @member = create(:user, operator: @operator, original_location: @location, current_location: @location)
    end
    host! "#{@operator.subdomain}.example.com"
  end

  def audit_rows
    Activity.unscoped.where(user_id: @member.id, kind: "admin_action").order(:id)
  end

  def api_headers(user)
    token = JWT.encode(
      { user_id: user.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )
    { "Authorization" => "Bearer #{token}", "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type" => "application/json" }
  end

  test "mobile admin archive records who did it" do
    post "/api/v1/admin/members/#{@member.id}/archive", headers: api_headers(@admin)

    assert_response :success
    row = audit_rows.last
    assert_equal "archived", row.payload["action"]
    assert_equal @admin.id, row.payload["actor_id"]
    assert_equal @admin.name, row.payload["actor_name"]
  end

  test "mobile admin unarchive and approve record too" do
    post "/api/v1/admin/members/#{@member.id}/unarchive", headers: api_headers(@admin)
    post "/api/v1/admin/members/#{@member.id}/approve", headers: api_headers(@admin)

    assert_equal %w[unarchived approved], audit_rows.last(2).map { |a| a.payload["action"] }
  end

  test "web archive records the actor" do
    log_in @admin
    get "/users/#{@member.slug || @member.id}/archive", env: default_env

    row = audit_rows.last
    assert_equal "archived", row.payload["action"]
    assert_equal @admin.id, row.payload["actor_id"]
  end

  test "web archive refused for an active member logs nothing" do
    ActsAsTenant.with_tenant(@operator) do
      plan = Plan.create!(operator: @operator, location: @location, name: "Flex", plan_type: "individual",
                          amount_in_cents: 22_500, interval: "month", available: true, visible: true)
      Subscription.create!(plan: plan, subscribable: @member, billable: @member,
                           active: true, start_date: Date.current)
    end
    log_in @admin

    get "/users/#{@member.slug || @member.id}/archive", env: default_env

    assert_equal 0, audit_rows.count
  end

  test "self-service account deletion logs itself" do
    delete "/api/v1/me", headers: api_headers(@member)

    assert_response :success
    row = audit_rows.last
    assert_equal "self_deleted", row.payload["action"]
    assert_equal @member.id, row.payload["actor_id"]
  end

  test "timeline labels read naturally" do
    h = ApplicationController.helpers
    assert_equal "Archived by Jamie", h.admin_action_label("action" => "archived", "actor_name" => "Jamie")
    assert_equal "Unapproved by Jamie", h.admin_action_label("action" => "unapproved", "actor_name" => "Jamie")
    assert_equal "Deleted their account", h.admin_action_label("action" => "self_deleted", "actor_name" => "X")
    assert_equal "Archived by staff", h.admin_action_label("action" => "archived")
  end

  test "a logging failure never blocks the admin action" do
    ActivityLogger.stubs(:log).raises(StandardError, "boom")

    post "/api/v1/admin/members/#{@member.id}/archive", headers: api_headers(@admin)

    assert_response :success
    assert @member.reload.archived
  end
end
