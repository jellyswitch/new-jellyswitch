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

  # Moderation delete from the mobile admin. Scoped to current_location so a
  # manager can only remove posts on the bulletin board they run — Post.find
  # on a bare id would let any admin delete any operator's post.
  def destroy
    post = Post.find_by(id: params[:id], location: current_location)
    return render json: { error: 'Not found' }, status: :not_found unless post

    post.destroy

    render json: { success: true }
  end
end
