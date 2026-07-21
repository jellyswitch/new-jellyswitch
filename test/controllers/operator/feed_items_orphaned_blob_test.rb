require "test_helper"

class Operator::FeedItemsOrphanedBlobTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @admin    = users(:cowork_tahoe_admin)
    host! "#{@operator.subdomain}.example.com"
    log_in @admin
  end

  # Regression: an admin deleted a day pass, but the feed item written at
  # purchase time still pointed at it. FeedItem#blob_relation used find, so
  # rendering /feed_items raised RecordNotFound — a 500 for every admin
  # until the orphan aged out of the feed.
  test "feed renders when a day-pass feed item points at a deleted day pass" do
    FeedItem.create!(
      operator: @operator,
      user: users(:cowork_tahoe_member),
      blob: { type: "day-pass", day_pass_id: -1 }
    )

    get "/feed_items", env: default_env

    assert_response :success
  end

  # Regression: feed_items has no DB foreign key to users, so a user deleted
  # without dependent cleanup (raw SQL, older sweeps) leaves feed items whose
  # nil `user` 500'd the whole feed — locking every admin out of their landing
  # page (TLH, 2026-07-20). Orphaned items must be skipped, not rendered.
  test "feed renders when a feed item's user has been deleted" do
    ghost = User.create!(
      name: "Ghost", email: "ghost-#{SecureRandom.hex(4)}@example.com",
      password: "password123", operator: @operator, admin_created: true,
    )
    FeedItem.create!(operator: @operator, user: ghost, blob: { type: "checkin" })
    Activity.where(user_id: ghost.id).delete_all # signup activity FK blocks the raw delete
    ghost.delete # raw delete, skipping callbacks — simulates the orphan

    get "/feed_items", env: default_env

    assert_response :success
  end

  test "feed renders when a reservation feed item points at a deleted reservation" do
    @operator.update!(reservation_notifications: true)
    FeedItem.create!(
      operator: @operator,
      user: users(:cowork_tahoe_member),
      blob: { type: "reservation", reservation_id: -1 }
    )

    get "/feed_items", env: default_env

    assert_response :success
  end
end
