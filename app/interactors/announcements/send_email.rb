class Announcements::SendEmail
  include Interactor

  delegate :announcement, to: :context

  def call
    AnnouncementEmailJob.perform_later(announcement)
  end
end