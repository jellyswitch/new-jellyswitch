require "test_helper"

# Coverage for the admin feedback inbox dismiss flow.
#
# Tapping "Dismiss" in My Messages > Feedback (mobile) hits
# POST /api/v1/admin/feedbacks/:id/dismiss and is expected to remove the
# conversation from the inbox. The action previously only marked the thread
# as read (last_read_at) and the index never filtered dismissed threads, so
# the conversation kept reappearing.
class Api::V1::Admin::FeedbacksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin    = users(:cowork_tahoe_admin)
    @member   = users(:cowork_tahoe_member)
    @operator = operators(:cowork_tahoe)

    @feedback = MemberFeedback.create!(
      operator: @operator,
      user: @member,
      comment: "The wifi keeps dropping",
    )

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

  def listed_feedback_ids
    JSON.parse(response.body).map { |f| f["id"] }
  end

  test "dismiss removes the thread from the feedback inbox list" do
    get "/api/v1/admin/feedbacks", headers: headers
    assert_response :success
    assert_includes listed_feedback_ids, @feedback.id

    post "/api/v1/admin/feedbacks/#{@feedback.id}/dismiss", headers: headers
    assert_response :success

    get "/api/v1/admin/feedbacks", headers: headers
    assert_response :success
    assert_not_includes listed_feedback_ids, @feedback.id
  end

  test "dismiss persists dismissed_at on the thread" do
    post "/api/v1/admin/feedbacks/#{@feedback.id}/dismiss", headers: headers
    assert_response :success

    assert_not_nil @feedback.reload.dismissed_at
  end
end
