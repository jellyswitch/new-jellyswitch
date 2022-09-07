class FeedItems::SaveComment
  include Interactor

  def call
    @feed_item = context.feed_item
    @params = context.params
    @user = context.user

    @feed_item_comment = @feed_item.feed_item_comments.new(@params)
    @feed_item_comment.user_id = @user.id
    
    if !@feed_item_comment.save
      context.fail!(message: "Couldn't save feed item comment.")
    end

    @feed_item.updated_at = @feed_item_comment.created_at

    if !@feed_item.save
      msg = "Unable to updated feed item #{@feed_item.id} upon comment #{@feed_item_comment.id}"
      context.fail!(message: msg)
    end

    context.notifiable = @feed_item_comment
    context.feed_item_comment = @feed_item_comment
  end
end