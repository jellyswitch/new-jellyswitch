class AnnouncementEmailJob < ApplicationJob
  queue_as :default

  def perform(announcement)
    announcement.operator.users.all.each do |user|
      if user.admin_of_location?(announcement.location) || user.superadmin? || user.member_at_location?(announcement.location)
        JellyswitchMail.new(announcement.operator, dry_run: !Rails.env.production?).announcement(announcement, user)
      end
    end
  end
end
