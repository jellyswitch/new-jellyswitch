class Api::V1::Admin::AnnouncementsController < Api::V1::Admin::BaseController
  def index
    announcements = Announcement.where(operator: current_tenant)
      .order(created_at: :desc)
      .limit(30)

    render json: announcements.map { |a| announcement_json(a) }
  end

  def create
    announcement = Announcement.new(
      body: params[:body],
      user: current_api_user,
      operator: current_tenant,
      location: current_location,
    )

    if announcement.save
      CreateNotificationsAsync.call(notifiable: announcement)
      render json: announcement_json(announcement), status: :created
    else
      render_error(announcement.errors.full_messages.join(', '))
    end
  end

  private

  def announcement_json(a)
    {
      id: a.id,
      body: a.body,
      user_name: a.user&.name,
      created_at: a.created_at,
    }
  end
end
