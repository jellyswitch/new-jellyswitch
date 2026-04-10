class Api::V1::AnnouncementsController < Api::V1::BaseController
  def index
    announcements = Announcement.where(operator: current_tenant, location: current_location)
      .order(created_at: :desc)
      .limit(20)

    render json: announcements.map { |a|
      {
        id: a.id,
        body: a.body,
        author: a.user&.name,
        created_at: a.created_at.strftime("%B %e, %Y"),
      }
    }
  end
end
