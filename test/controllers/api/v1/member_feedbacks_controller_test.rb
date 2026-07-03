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

  # Regression: a member replying INSIDE an existing conversation
  # (MessageDetailScreen → feedbackAPI.reply → #reply) must reach staff the
  # same way #create does. The old #reply did a bare reply.save with no
  # notification pipeline, so the admin push never fired and the
  # management-feed card was never refreshed — a real member's follow-up
  # ("I booked a room but it's not showing") sat unanswered because nobody
  # was alerted. Assert the feed card now reflects the latest reply.
  test "reply surfaces the member's message to the management feed (not a silent save)" do
    thread = MemberFeedback.create!(
      user: @member, operator: @operator, location: @location, comment: nil,
    )
    FeedbackReply.create!(
      member_feedback: thread, user: users(:cowork_tahoe_admin),
      operator: @operator, body: "Hi! Welcome to Cowork Tahoe.",
    )

    assert_difference -> { thread.feedback_replies.count }, +1 do
      post "/api/v1/member_feedbacks/#{thread.id}/reply",
           params: { body: "Following up on my earlier question" }.to_json,
           headers: headers
    end
    assert_response :created

    card = FeedItem.unscoped.for_operator(@operator)
                   .where("blob->>'type' = ?", "feedback")
                   .where("blob->>'member_feedback_id' = ?", thread.id.to_s)
                   .order(:created_at).first
    assert card, "a feedback feed card must exist for the thread after a member reply"
    assert_equal "Following up on my earlier question", card.blob["body"],
      "the management-feed card must reflect the member's latest reply"
  end

  test "index and show include created_at_iso so the app can render local date + time" do
    post "/api/v1/member_feedbacks", params: { body: "When does the sauna open?" }.to_json, headers: headers
    assert_response :success

    get "/api/v1/member_feedbacks", headers: headers
    assert_response :success
    thread = JSON.parse(response.body).first
    assert_match(/\A\d{4}-\d{2}-\d{2}T/, thread["created_at_iso"],
      "thread list must carry an ISO instant alongside the legacy date string")

    get "/api/v1/member_feedbacks/#{thread["id"]}", headers: headers
    assert_response :success
    body = JSON.parse(response.body)
    assert_match(/\A\d{4}-\d{2}-\d{2}T/, body["created_at_iso"])
    body["replies"].each do |reply|
      assert_match(/\A\d{4}-\d{2}-\d{2}T/, reply["created_at_iso"],
        "every reply must carry created_at_iso")
    end
  end
end
