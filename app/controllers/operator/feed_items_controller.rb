class Operator::FeedItemsController < Operator::BaseController
  def index
    render_index
    authorize @feed_items
    new_feed_item
    sidebar_items
  end

  def show
    find_feed_item
    authorize @feed_item
    background_image
    sidebar_items
  end

  def create
    authorize FeedItem.new

    result = CreatePostFeedItem.call(
      blob: {text: feed_item_params[:text], type: "post"},
      user: current_user,
      operator: current_tenant,
      photos: feed_item_params[:photos]
    )

    if result.success?
      flash[:success] = "Posted!"
      turbolinks_redirect(feed_items_path, action: "restore")
    else
      flash[:error] = result.message
      turbolinks_redirect(feed_items_path, action: "restore")
    end
  end

  def destroy
    find_feed_item
    authorize @feed_item

    if @feed_item.destroy
      flash[:success] = "Deleted."
      turbolinks_redirect(feed_items_path, action: "restore")
    else
      flash[:error] = "Unable to delete that item."
      turbolinks_redirect(referrer_or_root)
    end
  end

  private

  def render_index
    background_image
    find_feed_items
  end

  def sidebar_items
    @member_feedbacks = current_tenant.member_feedbacks.recent
    @unapproved_users = current_tenant.users.members.unapproved
    @due_invoices = current_tenant.invoices.due.order('date DESC')
    @delinquent_invoices = current_tenant.invoices.delinquent.order('date DESC')
  end

  def new_feed_item
    @feed_item = FeedItem.new
  end

  def find_feed_items
    @pagy, @feed_items = pagy(FeedItem.for_operator(current_tenant).order('created_at DESC'))
  end

  def feed_item_params
    params.require(:feed_item).permit(:text, photos: [])
  end

  def find_feed_item(key=:id)
    @feed_item = FeedItem.find(params[key])
  end
end
