class Api::V1::PostRepliesController < Api::V1::BaseController
  def create
    # Scope to the caller's location so a member can't reply onto another
    # operator's board (Post.find is global in the API — no tenant scope here).
    post = Post.where(location: current_location).find_by(id: params[:post_id])
    return render_error("Post not found", status: :not_found) unless post

    reply = post.post_replies.build(user: current_api_user)
    reply.content = params[:body] if params[:body].present?

    if reply.save
      render json: reply_json(reply), status: :created
    else
      render_error(reply.errors.full_messages.first)
    end
  end

  private

  def reply_json(r)
    {
      id: r.id,
      body: r.content&.to_plain_text,
      html_body: r.content&.to_s,
      author: r.user&.name,
      author_photo_url: (r.user&.profile_photo&.attached? ? url_for(r.user.profile_photo) : nil rescue nil),
      created_at: r.created_at.iso8601,
      created_at_label: r.created_at.strftime("%B %e, %Y at %l:%M %p"),
    }
  end
end
