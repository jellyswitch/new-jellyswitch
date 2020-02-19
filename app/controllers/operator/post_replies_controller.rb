class Operator::PostRepliesController < Operator::BaseController
  include PostsHelper
  before_action :background_image

  def create
    @post_reply = PostReply.new(post_reply_params)
    @post_reply.user = current_user

    if @post_reply.save
      turbolinks_redirect(post_path(@post_reply.post))
    else
      flash[:error] = "Something went wrong."
      turbolinks_redirect(post_path(@post_reply.post), action: "replace")
    end
  end
end