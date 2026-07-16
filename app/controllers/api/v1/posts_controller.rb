class Api::V1::PostsController < Api::V1::BaseController
  def index
    posts = Post.where(location: current_location)
      .order(created_at: :desc)
      .limit(params[:limit] || 30)
      .offset(params[:offset] || 0)

    render json: posts.map { |p| post_json(p) }
  end

  def show
    # Scope to the caller's location — a bare Post.find is global in the API
    # (no tenant default_scope here), leaking other operators' boards.
    post = Post.where(location: current_location).find_by(id: params[:id])
    return render_error("Post not found", status: :not_found) unless post

    replies = post.post_replies.order(:created_at).includes(user: { profile_photo_attachment: :blob }).map { |r|
      {
        id: r.id,
        body: r.content&.to_plain_text,
        html_body: r.content&.to_s,
        author: r.user&.name,
        author_photo_url: r.user&.profile_photo&.attached? ? url_for(r.user.profile_photo) : nil,
        created_at: r.created_at.iso8601,
        created_at_label: r.created_at.strftime("%B %e at %l:%M %p"),
      }
    }

    render json: post_json(post).merge(replies: replies)
  end

  def create
    post = Post.new(
      title: params[:subject],
      user: current_api_user,
      location: current_location,
    )
    post.content = params[:body] if params[:body].present?

    if post.save
      render json: post_json(post), status: :created
    else
      render_error(post.errors.full_messages.first)
    end
  end

  private

  def post_json(post)
    reactions = post.post_reactions.group(:emoji).count
    my_emojis = post.post_reactions.where(user_id: current_api_user.id).pluck(:emoji)
    {
      id: post.id,
      body: post.content&.to_plain_text,
      html_body: post.content&.to_s,
      subject: post.title,
      author: post.user&.name,
      author_id: post.user&.id,
      author_photo_url: post.user&.profile_photo&.attached? ? url_for(post.user.profile_photo) : nil,
      reply_count: post.post_replies.count,
      created_at: post.created_at.iso8601,
      created_at_label: post.created_at.strftime("%B %e, %Y"),
      reactions: reactions.map { |emoji, count| { emoji: emoji, count: count, reacted: my_emojis.include?(emoji) } },
    }
  end
end
