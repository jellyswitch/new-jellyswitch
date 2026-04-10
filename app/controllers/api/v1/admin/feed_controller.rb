class Api::V1::Admin::FeedController < Api::V1::Admin::BaseController
  def index
    items = FeedItem.where(operator: current_tenant)
                    .order(created_at: :desc)

    items = apply_filter(items, params[:filter]) if params[:filter].present?

    items = items.offset(params[:offset].to_i).limit(30)

    render json: items.map { |fi| feed_item_json(fi) }
  end

  def create
    feed_item = FeedItem.create!(
      blob: { 'type' => 'post', 'body' => params[:body], 'user_name' => current_api_user.name },
      operator: current_tenant,
      location: current_location,
      user: current_api_user
    )

    render json: feed_item_json(feed_item), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render_error(e.message)
  end

  def comment
    feed_item = FeedItem.find(params[:id])

    comment = feed_item.feed_item_comments.create!(
      comment: params[:body],
      user: current_api_user
    )

    render json: {
      id: comment.id,
      body: comment.comment,
      user_name: comment.user.name,
      created_at: comment.created_at
    }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render_error(e.message)
  end

  def destroy
    feed_item = FeedItem.find(params[:id])
    feed_item.destroy

    render json: { success: true }
  end

  private

  def apply_filter(items, filter)
    case filter
    when 'questions'
      items.where("blob->>'body' LIKE '%?%' OR blob->>'subject' LIKE '%?%'")
    when 'activity'
      items.where("blob->>'type' IN (?)", %w[feedback day-pass reservation subscription checkin paid-room-reservation])
    when 'notes'
      items.where("blob->>'type' = ?", 'post')
    when 'financial'
      items.where("blob->>'type' = ? OR expense = ?", 'refund', true)
    else
      items
    end
  end

  def feed_item_json(fi)
    {
      id: fi.id,
      type: fi.blob['type'],
      body: fi.blob['body'] || fi.blob['subject'],
      user_name: fi.blob['user_name'],
      amount: fi.blob['amount'],
      created_at: fi.created_at,
      expense: fi.expense,
      comment_count: fi.feed_item_comments.count
    }
  end
end
