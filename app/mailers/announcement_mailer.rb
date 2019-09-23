# typed: true
class AnnouncementMailer < ApplicationMailer

  def notification(announcement, recipient)
    @announcement = announcement
    @recipient = recipient

    mail to: recipient.email, subject: "Announcement from #{announcement.operator.name}", from: "#{announcement.user.name} <#{announcement.user.email}>"
  end
end