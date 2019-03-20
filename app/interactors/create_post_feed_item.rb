class CreatePostFeedItem
  include Interactor

  def call
    @feed_item = FeedItem.new
    @feed_item.blob = context.blob
    @feed_item.operator = context.operator
    @feed_item.user = context.user

    photos = context.photos
    if photos.present?
      @feed_item.photos.attach(photos)
    end

    if !@feed_item.save
      context.fail!(message: "Unable to post management note.")
    end

    result = PushNotifier.call(
      message: "#{@feed_item.user.name} posted a new management note",
      operator: @feed_item.operator
    )

    if !result.success?
      Rollbar.error("Error pushing notification: #{result.message}")
    end
  end
end