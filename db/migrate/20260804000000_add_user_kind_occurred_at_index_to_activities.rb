class AddUserKindOccurredAtIndexToActivities < ActiveRecord::Migration[7.2]
  # User#milestone_door_punch_ids computes "earliest door_punch at/after each
  # join/payment anchor" in SQL: a range scan over the anchor kinds plus a
  # LIMIT-1 LATERAL probe per anchor, every predicate shaped
  # (user_id, kind, occurred_at). The existing (user_id, occurred_at) index
  # would have to walk past every other kind's rows to satisfy the kind filter;
  # this one makes each probe a single index descent.
  #
  # Built CONCURRENTLY (no write lock — activities is large in prod: every door
  # punch, email event, and payment lands here). disable_ddl_transaction! is
  # required for that, and if_not_exists makes the release-phase retry-safe if
  # a build is interrupted partway.
  disable_ddl_transaction!

  def change
    add_index :activities, [:user_id, :kind, :occurred_at],
              algorithm: :concurrently, if_not_exists: true
  end
end
