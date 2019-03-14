class Operator::FeedItemCommentsController < Operator::BaseController
  def create
    find_feed_item
    authorize @feed_item

    @feed_item_comment = @feed_item.feed_item_comments.new(feed_item_comment_params)
    @feed_item_comment.user_id = current_user.id
    
    if @feed_item_comment.save
      flash[:success] = "Comment posted."
    else
      flash[:error] = "Couldn't post comment."
    end

    turbolinks_redirect(feed_item_path(@feed_item))
  end

  private

  def find_feed_item(key=:feed_item_id)
    @feed_item = FeedItem.find(params[key])
  end

  def feed_item_comment_params
    params.require(:feed_item_comment).permit(:comment)
  end
end