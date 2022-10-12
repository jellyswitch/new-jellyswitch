class AnnouncementEmailJob < ApplicationJob
  queue_as :default

  def perform(announcement)
    announcement.operator.users.all.each do |user|
      if user.admin? || user.superadmin? || user.member_at_operator?(announcement.operator)
        JellyswitchMail.new(announcement.operator, dry_run: !Rails.env.production?).announcement(announcement, user)
      end
    end
  end
end
