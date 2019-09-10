module AnnouncementHelper
  def find_announcements
    @pagy, @announcements = pagy(current_tenant.announcements.order("created_at DESC"))
  end
end