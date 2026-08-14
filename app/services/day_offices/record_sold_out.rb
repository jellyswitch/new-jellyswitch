# Admin-feed visibility for turned-away Day Office demand (ADR 0026 family):
# a member who tried to buy or schedule a Day Office and got "sold out" is
# demand the pool couldn't hold — staff asked to see it in the management feed
# so they can react (call the member back, adjust the pool, add capacity).
#
# Best-effort like DayOffices::Notify: feed bookkeeping must never break the
# member-facing 422 (which every caller renders AFTER any failed organizer has
# finished rolling back — so this row is written outside that unwind and
# survives it). One card per member+day: retaps and create/schedule races
# collapse into the first card.
module DayOffices
  class RecordSoldOut
    def self.call(user:, day_pass_type:, day:, location:, operator:)
      return if user.nil? || day_pass_type.nil? || day.nil? || operator.nil?
      return if already_recorded?(operator, user, day)

      FeedItemCreator.create_feed_item(operator, location, user, {
        type: "day-office-sold-out",
        day_pass_type_id: day_pass_type.id,
        day: day.iso8601,
        text: "Wanted a #{day_pass_type.name} for #{day.strftime('%B %e').squish} — sold out.",
      })
    rescue => e
      Rails.logger.warn("DayOffices::RecordSoldOut failed: #{e.class}: #{e.message}")
      Honeybadger.notify(e) if defined?(Honeybadger)
      nil
    end

    def self.already_recorded?(operator, user, day)
      FeedItem.unscoped
              .where(operator_id: operator.id, user_id: user.id)
              .where("blob->>'type' = ?", "day-office-sold-out")
              .where("blob->>'day' = ?", day.iso8601)
              .exists?
    end
    private_class_method :already_recorded?
  end
end