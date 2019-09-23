class Announcements::SendEmail
  include Interactor

  delegate :announcement, to: :context

  def call
    announcement.operator.users.all.each do |user|
      if user.admin? || user.superadmin? || user.member?(announcement.operator)
        AnnouncementMailer.notification(announcement, user).deliver_later
      end
    end
  end
end