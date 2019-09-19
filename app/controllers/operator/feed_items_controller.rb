# typed: false
class Operator::FeedItemsController < Operator::BaseController
  before_action :background_image
  before_action :find_todays_events
  before_action :find_room_reservations

  include EventHelper

  def index
    if !current_tenant.onboarded? && !current_tenant.skip_onboarding?
      turbolinks_redirect(new_operator_onboarding_path, action: "replace")
    else
      find_feed_items
      @all_active = "active"
      @questions_active = nil
      @activity_active = nil
      @notes_active = nil
      @expenses_active = nil

      # what's happening

      authorize @feed_items
    end
  end

  def questions
    find_questions
    @all_active = nil
    @questions_active = "active"
    @activity_active = nil
    @notes_active = nil
    @expenses_active = nil
    authorize @feed_items
    render :index
  end

  def activity
    find_activity
    @all_active = nil
    @questions_active = nil
    @activity_active = "active"
    @notes_active = nil
    @expenses_active = nil
    authorize @feed_items
    render :index
  end

  def notes
    find_notes
    @all_active = nil
    @questions_active = nil
    @activity_active = nil
    @notes_active = "active"
    @expenses_active = nil
    authorize @feed_items
    render :index
  end

  def expenses
    find_expenses
    @all_active = nil
    @questions_active = nil
    @activity_active = nil
    @notes_active = nil
    @expenses_active = "active"
    authorize @feed_items
    render :index
  end

  def show
    find_feed_item
    authorize @feed_item
  end

  def new
    new_feed_item
    authorize @feed_item
  end

  def create
    authorize FeedItem.new
    
    result = CreatePostFeedItem.call(
      blob: { text: feed_item_params[:text], type: "post" },
      user: current_user,
      operator: current_tenant,
      photos: feed_item_params[:photos],
    )

    if result.success?
      flash[:success] = "Posted!"
      turbolinks_redirect(feed_items_path, action: "restore")
    else
      flash[:error] = result.message
      turbolinks_redirect(feed_items_path, action: "restore")
    end
  rescue => e
    Rollbar.error(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbolinks_redirect(referrer_or_root)
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
  rescue Exception => e
    Rollbar.error(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbolinks_redirect(referrer_or_root)
  end

  def set_expense_status
    find_feed_item
    turn_into_expense
    @comments = params[:comments] == "true"
    render :set_expense_status
  end

  def unset_expense_status
    find_feed_item
    not_an_expense
    @comments = params[:comments] == "true"
    render :set_expense_status
  end

  private

  def new_feed_item
    @feed_item = FeedItem.new
  end

  def find_feed_items
    @pagy, @feed_items = pagy(FeedItem.unscoped.for_operator(current_tenant).order("updated_at DESC"))
  end

  def find_questions
    @pagy, @feed_items = pagy(FeedItem.unscoped.questions.for_operator(current_tenant).order("updated_at DESC"))
  end

  def find_activity
    @pagy, @feed_items = pagy(FeedItem.unscoped.activity.for_operator(current_tenant).order("updated_at DESC"))
  end 

  def find_notes
    @pagy, @feed_items = pagy(FeedItem.unscoped.notes.for_operator(current_tenant).order("updated_at DESC"))
  end

  def find_expenses
    @pagy, @feed_items = pagy(FeedItem.unscoped.expenses.for_operator(current_tenant).order("updated_at DESC"))
  end

  def feed_item_params
    params.require(:feed_item).permit(:text, photos: [])
  end

  def find_feed_item(key = :id)
    @feed_item = FeedItem.unscoped.find(params[key])
  end

  def turn_into_expense
    @feed_item.parse_amount
    @feed_item.set_expense
    @feed_item.save
  end

  def not_an_expense
    @feed_item.unset_expense
    @feed_item.save
  end

  def find_room_reservations
    @reservations = current_location.rooms.map do |room|
      room.reservations.today
    end.flatten.uniq.count
  end
end
