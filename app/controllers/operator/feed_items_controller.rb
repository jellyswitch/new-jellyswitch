
class Operator::FeedItemsController < Operator::BaseController
  include EventHelper
  include UsersHelper
  include FeedItemsHelper
  include ActionView::Helpers::SanitizeHelper

  before_action :background_image
  before_action :find_todays_events
  before_action :find_room_reservations
  before_action :set_unapproved_users
  before_action :find_upcoming_renewals
  before_action :find_outstanding_invoices
  before_action :find_upcoming_childcare_reservations

  def index
    if !current_tenant.onboarded? && !current_tenant.skip_onboarding?
      turbo_redirect(new_operator_onboarding_path, action: "replace")
    else
      find_feed_items
      @all_active = "active"
      @questions_active = nil
      @activity_active = nil
      @notes_active = nil
      @financial_active = nil

      authorize @feed_items
    end
  end

  def questions
    find_questions
    @all_active = nil
    @questions_active = "active"
    @activity_active = nil
    @notes_active = nil
    @financial_active = nil
    authorize @feed_items
    render :index
  end

  def activity
    find_activity
    @all_active = nil
    @questions_active = nil
    @activity_active = "active"
    @notes_active = nil
    @financial_active = nil
    authorize @feed_items
    render :index
  end

  def notes
    find_notes
    @all_active = nil
    @questions_active = nil
    @activity_active = nil
    @notes_active = "active"
    @financial_active = nil
    authorize @feed_items
    render :index
  end

  def financial
    find_financial
    @all_active = nil
    @questions_active = nil
    @activity_active = nil
    @notes_active = nil
    @financial_active = "active"
    authorize @feed_items
    render :index
  end

  def show
    find_feed_item
    authorize @feed_item

    if @feed_item.type == "feedback" && @feed_item.member_feedback.present?
      redirect_to member_feedback_path(@feed_item.member_feedback)
      return
    end
  end

  def new
    new_feed_item
    authorize @feed_item
  end

  def create
    authorize FeedItem.new

    # The button no longer client-side-gates on content (that broke with Trix),
    # so guard empty notes here instead.
    if ActionText::Content.new(feed_item_params[:text].to_s).to_plain_text.strip.blank?
      flash[:error] = "Write something before posting a note."
      return turbo_redirect(new_feed_item_path, action: restore_if_possible)
    end

    result = FeedItems::Create.call(
      # to_plain_text (not strip_tags): decodes HTML entities and turns block
      # elements into newlines, so blob['text'] reads cleanly everywhere
      # (notably the mobile feed). The full rich text is stored separately below.
      blob: { text: ActionText::Content.new(feed_item_params[:text].to_s).to_plain_text, type: "post" },
      text: feed_item_params[:text],
      user: current_user,
      operator: current_tenant,
      location: current_location,
      photos: feed_item_params[:photos],
    )

    if result.success?
      # Cross-post the note onto any tagged CUSTOMER's record (silent). See ADR 0006.
      Crm::CrossPostFeedTags.call(
        text: ActionText::Content.new(feed_item_params[:text].to_s).to_plain_text,
        source: result.feed_item,
        author: current_user,
      )
      flash[:success] = "Posted!"
      turbo_redirect(feed_items_path, action: restore_if_possible)
    else
      flash[:error] = result.message
      turbo_redirect(feed_items_path, action: restore_if_possible)
    end
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
  end

  def destroy
    find_feed_item
    authorize @feed_item

    if @feed_item.destroy
      flash[:success] = "Deleted."
      turbo_redirect(feed_items_path, action: restore_if_possible)
    else
      flash[:error] = "Unable to delete that item."
      turbo_redirect(referrer_or_root)
    end
  rescue Pundit::NotAuthorizedError, ActiveRecord::RecordNotFound
    raise
  rescue => e
    Honeybadger.notify(e)
    flash[:error] = "An error occurred: #{e.message}"
    turbo_redirect(referrer_or_root)
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
end
