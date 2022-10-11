class Operator::AnnouncementsController < Operator::BaseController
  include AnnouncementHelper
  before_action :background_image

  def index
    find_announcements
    authorize @announcements
  end

  def new
    @announcement = Announcement.new
    authorize @announcement
  end

  def create
    authorize Announcement.new

    result = Announcements::Create.call(
      body: announcement_params[:body],
      user: current_user,
      operator: current_tenant
    )
    
    if result.success?
      flash[:success] = "Announcement posted."
      turbo_redirect(feed_items_path, action: restore_if_possible)
    else
      flash[:error] = result.message
      turbo_redirect(new_announcement_path, action: restore_if_possible)
    end
  end
end