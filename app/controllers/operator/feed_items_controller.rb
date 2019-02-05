class Operator::FeedItemsController < Operator::ApplicationController
  def index
    render_index
    authorize @feed_items
    new_feed_item
  end

  def show
    find_feed_item
    authorize @feed_item
    background_image
  end

  def create
    @feed_item = FeedItem.new
    @feed_item.blob = {text: feed_item_params[:text], type: "post"}
    @feed_item.operator = current_tenant
    @feed_item.user = current_user

    authorize @feed_item

    if @feed_item.save
      flash[:success] = "Posted!"
      redirect_to feed_items_path
    else
      flash[:error] = "Something went wrong."
      render_index
    end
  end

  private

  def render_index
    background_image
    find_feed_items
  end

  def new_feed_item
    @feed_item = FeedItem.new
  end

  def find_feed_items
    @feed_items = FeedItem.for_operator(current_tenant).order('created_at DESC').all
  end

  def feed_item_params
    params.require(:feed_item).permit(:text)
  end

  def find_feed_item(key=:id)
    @feed_item = FeedItem.find(params[key])
  end
end