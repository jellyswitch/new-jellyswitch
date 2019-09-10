class Operator::AnnouncementsController < Operator::BaseController
  include AnnouncementHelper
  before_action :background_image

  def index
    find_announcements
  end

  def show
  end
end