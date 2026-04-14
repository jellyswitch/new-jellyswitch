class AnnouncementEmailJob < ApplicationJob
  queue_as :default

  def perform(announcement)
    announcement.operator.users.visible.each do |user|
      next if user.email_opted_out? || user.email_bounced? || user.marketing_suppressed?
      next unless should_receive_announcement?(user, announcement)

      UserMailer.announcement_email(announcement, user).deliver_now
    end
  end

  private

  def should_receive_announcement?(user, announcement)
    location = announcement.location

    # Admins and superadmins always get announcements
    return true if user.admin_of_location?(location) || user.superadmin?

    # Members must have an active paying relationship to receive announcements
    return false unless user.member_at_location?(location)

    # Must have an active subscription, day pass today, or active lease
    user.subscriptions.active.any? ||
      user.day_passes.where(day: Date.current).any? ||
      user.organization&.office_leases&.active&.any?
  end
end
