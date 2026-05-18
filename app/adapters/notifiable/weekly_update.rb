
module Notifiable
  class WeeklyUpdate < Notifiable::Default
    private

    def create_feed_item
      blob = {type: "weekly-update", weekly_update_id: id}
      # Weekly updates are system-generated, but FeedItem.user is currently
      # `belongs_to :user` (non-optional), so we still need *some* user
      # attached. Prefer an operator admin so the row is meaningful if any
      # caller introspects it directly. The API serializer (and the web
      # feed_item partial) both hide this user on weekly-update items.
      # Falls back to ::User.first only if the operator somehow has no
      # admins, which shouldn't happen in production.
      user = operator.users
                     .where(role: %w[admin superadmin general_manager community_manager])
                     .first || ::User.first
      FeedItemCreator.create_feed_item(operator, location, user, blob, created_at: created_at)
    end

    def deep_link_data
      { type: "weekly_update", resource_id: id, path: "/weekly_updates/#{id}" }
    end

    def should_send_notification?
      true
    end

    def message
      "Your weekly update has been posted in the feed. Take a look!"
    end

    def recipients
      operator.users.relevant_admins_of_location(location)
    end
  end
end
