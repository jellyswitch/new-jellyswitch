class Announcements::Save
  include Interactor

  delegate :body, :user, :operator, to: :context

  def call
    announcement = Announcement.new(
      body: body,
      user: user,
      operator: operator
    )

    if !announcement.save
      context.fail!(message: "Failed to save announcement.")
    end

    context.announcement = announcement
    context.notifiable = announcement
    context.members = true
  end
end