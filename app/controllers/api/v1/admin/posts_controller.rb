class Api::V1::Admin::PostsController < Api::V1::Admin::BaseController
  def index
    posts = Post.where(location: current_location)
      .order(created_at: :desc).limit(30)

    render json: posts.map { |p|
      {
        id: p.id,
        body: p.content&.to_plain_text,
        subject: p.title,
        author: p.user&.name,
        reply_count: p.post_replies.count,
        created_at: p.created_at.iso8601,
      }
    }
  end

  def destroy
    post = Post.find(params[:id])
    post.destroy

    render json: { success: true }
  end
end
