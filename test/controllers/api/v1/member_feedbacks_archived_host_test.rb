require "test_helper"

# Regression: Cowork Tahoe's configured space host pointed at an archived
# admin account. FeedbackReply refuses archived authors (#731), so the
# host-greeting seeder's create! turned a NEW member's very first message
# into a 500 (Honeybadger, 2026-08-19) and left an orphan empty thread.
# An archived host must be treated like no host at all: the greeting is
# skipped or re-authored by a live admin, and the member's message lands.
class Api::V1::MemberFeedbacksArchivedHostTest < ActionDispatch::IntegrationTest
  setup do
    @member   = users(:cowork_tahoe_member)
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)
    @admin    = users(:cowork_tahoe_admin)

    @token = JWT.encode(
      { user_id: @member.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )

    @member.member_feedbacks.destroy_all

    ActsAsTenant.with_tenant(@operator) do
      @archived_host = create(:user, operator: @operator, original_location: @location, current_location: @location)
      @archived_host.update!(archived: true)
      @location.update!(space_host_id: @archived_host.id)
    end
  end

  def headers
    {
      "Authorization"        => "Bearer #{@token}",
      "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type"         => "application/json",
    }
  end

  test "first message succeeds even though the configured host is archived" do
    assert_difference -> { @member.member_feedbacks.count }, +1 do
      post "/api/v1/member_feedbacks",
           params: { body: "What time can I get in tomorrow?" }.to_json,
           headers: headers
    end

    assert_response :created
    thread = @member.member_feedbacks.reload.order(:created_at).last
    bodies = thread.feedback_replies.order(:created_at).map(&:body) + [thread.comment]
    assert bodies.compact.any? { |b| b.include?("What time can I get in") },
           "the member's message must land somewhere on the thread"
    assert_equal 0, thread.feedback_replies.where(user_id: @archived_host.id).count,
                 "the archived host must not author anything"
  end

  test "space_host_for skips an archived configured host and finds a live admin" do
    helper = Object.new.extend(LandingHelper)
    host = ActsAsTenant.with_tenant(@operator) { helper.space_host_for(@location) }

    assert_not_nil host
    assert_not host.archived?
    assert_not_equal @archived_host.id, host.id
  end

  test "space_host_for never returns an archived fallback admin" do
    ActsAsTenant.with_tenant(@operator) do
      @location.update!(space_host_id: nil)
      helper = Object.new.extend(LandingHelper)
      host = helper.space_host_for(@location)
      assert(host.nil? || !host.archived?)
    end
  end

  test "EnsureHostGreeting leaves no orphan thread when the greeting cannot save" do
    ActsAsTenant.with_tenant(@operator) do
      FeedbackReply.any_instance.stubs(:save).returns(false)

      result = MemberFeedback::EnsureHostGreeting.call(
        user: @member, location: @location, operator: @operator, host: @admin
      )

      assert_nil result.member_feedback
      assert_equal 0, @member.member_feedbacks.count, "the empty thread shell must roll back"
    end
  end
end
