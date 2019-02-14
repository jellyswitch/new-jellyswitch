class Operator::FeedItemsController < Operator::BaseController
  def index
    render_index
    authorize @feed_items
    new_feed_item

    @member_feedbacks = current_tenant.member_feedbacks.recent
    @unapproved_users = current_tenant.users.members.unapproved
    @due_invoices = current_tenant.invoices.due.order('date DESC')
    @delinquent_invoices = current_tenant.invoices.delinquent.order('date DESC')
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
    photos = feed_item_params[:photos]
    if photos.present?
      @feed_item.photos.attach(feed_item_params[:photos])
    end

    if @feed_item.text.downcase.include?("spent")
      @feed_item.expense = true
    end

    authorize @feed_item

    if @feed_item.save
      flash[:success] = "Posted!"
      redirect_to feed_items_path
    else
      flash[:error] = "Something went wrong."
    end
  end

  def destroy
    find_feed_item
    authorize @feed_item

    if @feed_item.destroy
      flash[:success] = "Deleted."
      redirect_to feed_items_path
    else
      flash[:error] = "Unable to delete that item."
      redirect_to :back
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
    params.require(:feed_item).permit(:text, photos: [])
  end

  def find_feed_item(key=:id)
    @feed_item = FeedItem.find(params[key])
  end
end