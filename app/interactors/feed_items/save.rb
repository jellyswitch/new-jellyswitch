class FeedItems::Save
  include Interactor

  delegate :text, :blob, :operator, :location, :user, :photos, :created_at, :announcement, to: :context

  def call
    @feed_item = FeedItem.new
    @feed_item.blob = blob
    @feed_item.text = text
    @feed_item.operator = operator
    @feed_item.location = location
    @feed_item.user = user

    if @feed_item.type == "announcement"
      @feed_item.blob["announcement_id"] = announcement.id
    end

    if created_at.present?
      @feed_item.created_at = created_at
      @feed_item.updated_at = created_at
    end

    if photos.present?
      @feed_item.photos.attach(photos)
    end

    if @feed_item.is_expense_feed?
      @feed_item.parse_amount
      @feed_item.set_expense
    end

    if !@feed_item.save
      context.fail!(message: "Unable to post management note.")
    end

    if @feed_item.type == "announcement" && announcement.present?
      context.notifiable = announcement
    else
      context.notifiable = @feed_item
    end

    context.feed_item = @feed_item
    context.announcement = announcement
  end

  def rollback
    context.feed_item.destroy
  end
end
