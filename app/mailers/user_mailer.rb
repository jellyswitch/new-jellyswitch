
class UserMailer < ApplicationMailer
  helper ApplicationHelper
  helper LayoutHelper

  def password_reset(user, operator)
    @user = user
    @operator = operator

    mail to: user.email, subject: "#{@operator.name} password reset", from: "noreply@jellyswitch.com"
    recipients = User.superadmins.all.map {|u| u.email }
  end

  def event_registration(user, password, event)
    @user = user
    @password = password
    @event = event

    @host = ENV['ASSET_HOST']
    mail to: @user.email, subject: "You're all set for #{@event.title}!", from: "noreply@jellyswitch.com"
  end

  def event_cancellation(user, event_name, operator)
    @user = user
    @event_name = event_name
    @operator = operator
    
    @host = ENV['ASSET_HOST']
    mail to: @user.email, subject: "Cancelled: #{@event_name}", from: "noreply@jellyswitch.com"
  end
end