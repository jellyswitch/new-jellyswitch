
module FeedItemCreator
  # for pub/sub
  def self.create_feed_item(operator, location, user, blob, options = {})
    feed_item = FeedItem.new
    feed_item.operator = operator
    feed_item.location = location
    feed_item.user = user
    feed_item.blob = blob

    if options[:day].present?
      feed_item.created_at = options[:day]
      feed_item.updated_at = options[:day]
    end

    if options[:created_at].present?
      feed_item.created_at = options[:created_at]
      feed_item.updated_at = options[:created_at]
    end

    feed_item.save!
  end

  # Collapse a member-feedback conversation into a SINGLE feed card. If a feed
  # item already exists for this thread (same member_feedback_id), refresh it
  # to the latest message and let the updated_at bump float it to the top of
  # the feed — instead of stacking a brand-new card per reply.
  def self.upsert_feedback_feed_item(operator, location, user, blob, options = {})
    member_feedback_id = (blob[:member_feedback_id] || blob["member_feedback_id"]).to_s
    return create_feed_item(operator, location, user, blob, options) if member_feedback_id.blank?

    existing = FeedItem.unscoped
                       .for_operator(operator)
                       .where("blob->>'type' = ?", "feedback")
                       .where("blob->>'member_feedback_id' = ?", member_feedback_id)
                       .order(:created_at)
                       .first

    if existing
      existing.update!(blob: blob, user: user, location: location)
      existing
    else
      create_feed_item(operator, location, user, blob, options)
    end
  end

  def create_feed_item(operator, location, user, blob, options = {})
    return if user.class == Organization # don't create a feed item if the billable was an organization

    feed_item = FeedItem.new
    feed_item.operator = operator
    feed_item.location = location
    feed_item.user = user
    feed_item.blob = blob

    if options[:day].present?
      feed_item.created_at = options[:day]
      feed_item.updated_at = options[:day]
    end

    if options[:created_at].present?
      feed_item.created_at = options[:created_at]
      feed_item.updated_at = options[:created_at]
    end

    if !feed_item.save
      context.fail!(message: "Unable to generate feed item.")
    end

    operator.users.relevant_admins_of_location(feed_item.location).each do |admin_user|
      send_email_notification(admin_user, feed_item)
    end
    feed_item
  end

  def send_email_notification(user, feed_item)
    case feed_item.type
    when "feedback"
      FeedItemsMailer.member_feedback(user: user, feed_item: feed_item).deliver_later
    end
  end
end
