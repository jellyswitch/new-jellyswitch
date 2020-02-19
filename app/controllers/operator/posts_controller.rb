class Operator::PostsController < Operator::BaseController
  include PostsHelper
  before_action :background_image

  def index
    find_posts
    authorize @posts
  end

  def new
    @post = current_location.posts.new
    authorize @post
  end

  def create
    @post = current_location.posts.new(post_params)
    @post.user = current_user
    if @post.save
      turbolinks_redirect(post_path(@post))
    else
      flash[:error] = "Something went wrong."
      turbolinks_redirect(new_post_path, action: "replace")
    end
  end

  def show
    find_post
    authorize @post
  end
end