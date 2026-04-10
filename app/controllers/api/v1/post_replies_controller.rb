class Api::V1::PostRepliesController < Api::V1::BaseController
  def create
    post = Post.find(params[:post_id])
    reply = post.post_replies.build(
      body: params[:body],
      user: current_api_user,
      operator: current_tenant,
    )

    if reply.save
      render json: {
        id: reply.id,
        body: reply.body,
        author: reply.user&.name,
        created_at: reply.created_at.strftime("%B %e, %Y at %l:%M %p"),
      }, status: :created
    else
      render_error(reply.errors.full_messages.first)
    end
  end
end
