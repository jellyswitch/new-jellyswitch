# typed: true
class UserMailer < ApplicationMailer
  helper LayoutHelper

  def password_reset(user, operator)
    @user = user
    @operator = operator

    mail to: user.email, subject: "#{@operator.name} password reset", from: @operator.contact_email
    recipients = User.superadmins.all.map {|u| u.email }
  end

  def onboarding(user, password)
    @user = user
    @password = password

    from_addr = @user.operator.contact_email
    if from_addr.blank?
      from_addr = "noreply@jellyswitch.com"
    end

    mail to: @user.email, subject: "Welcome to #{user.operator.name}!", from: from_addr
  end

  def event_registration(user, password, event)
    @user = user
    @password = password
    @event = event

    from_addr = @user.operator.contact_email
    if from_addr.blank?
      from_addr = "noreply@jellyswitch.com"
    end
    
    mail to: @user.email, subject: "You're all set for #{@event.title}!", from: from_addr
  end
end