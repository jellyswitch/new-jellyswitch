require "test_helper"

# Coverage for /api/v1/member_feedbacks#create — the endpoint the React
# Native "Messages" screen calls when a member taps "New Message".
#
# Operator::MemberFeedbacksController#create already treats the member's
# inbox as one ongoing thread per location (appending new comments as
# replies to the existing MemberFeedback instead of spawning parallel
# ones), but the API path was missed when that fix landed — so mobile
# members were ending up with the auto-host-greeting in one thread and
# their own question stranded in a second thread the team wasn't
# watching.
class Api::V1::MemberFeedbacksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @member   = users(:cowork_tahoe_member)
    @operator = operators(:cowork_tahoe)
    @location = locations(:cowork_tahoe_location)

    @token = JWT.encode(
      { user_id: @member.id, operator_id: @operator.id, exp: 30.days.from_now.to_i },
      Rails.application.secret_key_base,
      "HS256",
    )

    # Keep this test focused on the consolidation logic; clear any
    # fixture-derived threads for this member so we can assert
    # "no thread exists → POST → one thread" cleanly.
    @member.member_feedbacks.destroy_all
  end

  def headers
    {
      "Authorization"        => "Bearer #{@token}",
      "X-Operator-Subdomain" => @operator.subdomain,
      "Content-Type"         => "application/json",
    }
  end

  test "create spawns a new MemberFeedback when the member has no existing thread" do
    assert_difference -> { @member.member_feedbacks.count }, +1 do
      assert_no_difference -> { FeedbackReply.where(user: @member).count } do
        post "/api/v1/member_feedbacks",
             params: { body: "First message ever" }.to_json,
             headers: headers
      end
    end

    assert_response :created
    body = JSON.parse(response.body)
    created = @member.member_feedbacks.reload.order(:created_at).last
    assert_equal "First message ever", created.comment
    assert_equal created.id, body["id"]
  end

  test "create appends a reply to the existing thread instead of spawning a parallel one" do
    existing = MemberFeedback.create!(
      user:     @member,
      operator: @operator,
      location: @location,
      comment:  nil,
    )
    # Simulate the host-greeting reply (what EnsureHostGreeting writes).
    FeedbackReply.create!(
      member_feedback: existing,
      user:            users(:cowork_tahoe_admin),
      operator:        @operator,
      body:            "Hi there! Welcome to Cowork Tahoe.",
    )

    assert_no_difference -> { @member.member_feedbacks.count },
      "second member message must not create a parallel MemberFeedback thread" do
      assert_difference -> { existing.feedback_replies.count }, +1 do
        post "/api/v1/member_feedbacks",
             params: { body: "Do you have call rooms for zoom calls?" }.to_json,
             headers: headers
      end
    end

    assert_response :created
    body = JSON.parse(response.body)
    assert_equal existing.id, body["id"], "response should reference the existing thread, not a new one"
    assert_equal "Do you have call rooms for zoom calls?",
      existing.feedback_replies.order(:created_at).last.body
  end
end
