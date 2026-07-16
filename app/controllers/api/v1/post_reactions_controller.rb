class Api::V1::PostReactionsController < Api::V1::BaseController
  # POST /api/v1/posts/:post_id/reactions  body: { emoji: "👍" }
  # Toggles the reaction for the current user on this post.
  def create
    # Scope to the caller's location (Post.find is global in the API) so a
    # member can't react onto another operator's board.
    post = Post.where(location: current_location).find_by(id: params[:post_id])
    return render_error("Post not found", status: :not_found) unless post

    emoji = params[:emoji].to_s
    return render_error('Invalid emoji') unless PostReaction::ALLOWED_EMOJIS.include?(emoji)

    existing = post.post_reactions.find_by(user: current_api_user, emoji: emoji)
    if existing
      existing.destroy
      render json: summary_for(post)
    else
      post.post_reactions.create!(user: current_api_user, emoji: emoji)
      render json: summary_for(post)
    end
  end

  private

  def summary_for(post)
    my_emojis = post.post_reactions.where(user_id: current_api_user.id).pluck(:emoji)
    {
      post_id: post.id,
      reactions: post.post_reactions.group(:emoji).count.map { |emoji, count|
        { emoji: emoji, count: count, reacted: my_emojis.include?(emoji) }
      },
    }
  end
end
