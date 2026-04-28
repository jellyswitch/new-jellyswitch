module PostsHelper
  def find_posts
    # Unauthenticated scanners hit /posts/* with no session, so current_location
    # is nil. Surface as a 404 (Rails handles RecordNotFound globally) instead
    # of NoMethodError on nil.
    raise ActiveRecord::RecordNotFound if current_location.nil?
    @posts = current_location.posts.order("created_at DESC")
  end

  def find_post(key=:id)
    raise ActiveRecord::RecordNotFound if current_location.nil?
    @post = current_location.posts.find(params[key])
  end

  def post_params
    params.require(:post).permit(:content, :title)
  end

  def post_reply_params
    params.require(:post_reply).permit(:content, :post_id)
  end
end