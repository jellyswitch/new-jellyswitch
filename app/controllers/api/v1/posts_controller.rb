class Api::V1::PostsController < Api::V1::BaseController
  def index
    posts = Post.where(location: current_location)
      .order(created_at: :desc)
      .limit(params[:limit] || 30)
      .offset(params[:offset] || 0)

    render json: posts.map { |p| post_json(p) }
  end

  def show
    post = Post.find(params[:id])
    replies = post.post_replies.order(:created_at).map { |r|
      {
        id: r.id,
        body: r.body,
        author: r.user&.name,
        created_at: r.created_at.strftime("%B %e, %Y at %l:%M %p"),
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
    {
      id: post.id,
      body: post.content&.to_plain_text,
      subject: post.title,
      author: post.user&.name,
      reply_count: post.post_replies.count,
      created_at: post.created_at.strftime("%B %e, %Y"),
    }
  end
end
