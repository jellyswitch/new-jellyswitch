
class UserMailerPreview < ActionMailer::Preview
  def event_registration
    UserMailer.event_registration(User.first, "pizza123", Event.last)
  end
end