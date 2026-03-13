class AnnouncementEmailJob < ApplicationJob
  queue_as :default

  def perform(announcement)
    announcement.operator.users.all.each do |user|
      if user.admin_of_location?(announcement.location) || user.superadmin? || user.member_at_location?(announcement.location)
        UserMailer.announcement_email(announcement, user).deliver_now
      end
    end
  end
end
