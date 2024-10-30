module AnnouncementHelper
  def find_announcements
    @pagy, @announcements = pagy(current_location.announcements.order("created_at DESC"))
  end

  def announcement_params
    params.require(:announcement).permit([:body])
  end
end