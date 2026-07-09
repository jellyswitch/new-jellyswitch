class BackfillInterestTagsFromConcierge < ActiveRecord::Migration[7.1]
  # Seed Interest tags from what people already asked the concierge about. Every
  # concierge chat logs an Activity (kind: "chat") with the intent in its
  # payload; InterestTag.record_from_concierge_intent maps office / conference
  # room / day pass / membership intents to a tag (source: concierge, and
  # sticky-safe so it never clobbers a staff tag — none exist yet, but correct).
  def up
    seeded = 0
    ActsAsTenant.without_tenant do
      Activity.where(kind: "chat").find_each do |activity|
        intent = activity.payload.is_a?(Hash) ? activity.payload["intent"] : nil
        next if intent.blank?
        user = activity.user
        next unless user

        tag = InterestTag.record_from_concierge_intent(user, intent)
        seeded += 1 if tag&.persisted?
      end
    end
    say "Seeded/updated #{seeded} interest tags from concierge chats"
  end

  def down
    # Only the concierge-sourced tags; leave staff / other behavioral tags.
    ActsAsTenant.without_tenant { InterestTag.where(source: "concierge").delete_all }
  end
end
