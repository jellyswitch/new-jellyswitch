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

  # --- Reply collision check (send-time 409 guard) -------------------------
  #
  # Two admins race to answer the same thread. The reply POST carries the
  # highest staff-reply id the sender had loaded (last_seen_reply_id); if the
  # thread gained a staff reply since, the server answers 409 with the
  # intervening replies and saves nothing. Param absent = legacy behavior.
  # "Staff" mirrors FeedbackReply#from_admin?: any author who isn't the
  # thread's member.

  def staff_reply!(body = "Yes, dogs are fine on Fridays!")
    @feedback.feedback_replies.create!(user: @admin, operator: @operator, body: body)
  end

  def member_reply!(body = "Also, what about Saturday?")
    @feedback.feedback_replies.create!(user: @member, operator: @operator, body: body)
  end

  # last_seen_reply_id must distinguish null (present, saw none) from absent
  # (legacy client), so the body is posted as raw JSON.
  def post_reply(payload)
    post "/api/v1/admin/feedbacks/#{@feedback.id}/reply",
      params: payload.to_json, headers: headers
  end

  test "reply without last_seen_reply_id keeps legacy behavior even when a staff reply exists" do
    staff_reply!
    assert_difference -> { @feedback.feedback_replies.count }, 1 do
      post_reply(body: "Duplicate from an old app build")
    end
    assert_response :created
  end

  test "reply with fresh last_seen_reply_id is created" do
    seen = staff_reply!
    assert_difference -> { @feedback.feedback_replies.count }, 1 do
      assert_enqueued_with(job: SendNotificationsJob) do
        post_reply(body: "Follow-up", last_seen_reply_id: seen.id)
      end
    end
    assert_response :created
  end

  test "reply with stale last_seen_reply_id gets 409 with the intervening staff reply and saves nothing" do
    seen = staff_reply!("First answer")
    unseen = staff_reply!("Jamie's answer that raced in")

    assert_no_difference -> { @feedback.feedback_replies.count } do
      assert_no_enqueued_jobs only: SendNotificationsJob do
        post_reply(body: "My duplicate answer", last_seen_reply_id: seen.id)
      end
    end
    assert_response :conflict

    conflicts = JSON.parse(response.body)["conflicts"]
    assert_equal 1, conflicts.length
    assert_equal unseen.id, conflicts[0]["id"]
    assert_equal "Jamie's answer that raced in", conflicts[0]["body"]
    assert_equal @admin.name, conflicts[0]["author"]
    assert conflicts[0]["created_at"].present?
  end

  test "reply with null last_seen_reply_id gets 409 when any staff reply exists" do
    staff_reply!
    assert_no_difference -> { @feedback.feedback_replies.count } do
      post_reply(body: "I saw an empty thread", last_seen_reply_id: nil)
    end
    assert_response :conflict
  end

  test "reply with null last_seen_reply_id is created when no staff reply exists" do
    member_reply! # member replies alone must not block
    assert_difference -> { @feedback.feedback_replies.count }, 1 do
      post_reply(body: "First staff answer", last_seen_reply_id: nil)
    end
    assert_response :created
  end

  test "a newer member reply does not trigger a conflict" do
    seen = staff_reply!
    member_reply!
    assert_difference -> { @feedback.feedback_replies.count }, 1 do
      post_reply(body: "Answering the follow-up", last_seen_reply_id: seen.id)
    end
    assert_response :created
  end

  test "last_seen_reply_id from another thread is treated as saw-none" do
    other = MemberFeedback.create!(operator: @operator, user: @member, comment: "Other thread")
    foreign = other.feedback_replies.create!(user: @admin, operator: @operator, body: "elsewhere")
    staff_reply!

    assert_no_difference -> { @feedback.feedback_replies.count } do
      post_reply(body: "Cross-thread id", last_seen_reply_id: foreign.id)
    end
    assert_response :conflict
  end

  test "garbage last_seen_reply_id type fails closed as saw-none, not 500" do
    staff_reply!
    assert_no_difference -> { @feedback.feedback_replies.count } do
      post_reply(body: "Client sent a mangled param", last_seen_reply_id: { x: 1 })
    end
    assert_response :conflict
  end

  test "send-anyway with the conflicting reply id as new baseline is created" do
    staff_reply!("First answer")
    conflict = staff_reply!("Jamie's answer")

    assert_difference -> { @feedback.feedback_replies.count }, 1 do
      post_reply(body: "Sending anyway on purpose", last_seen_reply_id: conflict.id)
    end
    assert_response :created
  end
end
