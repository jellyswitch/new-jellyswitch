# typed: true
class UserMailer < ApplicationMailer

  def password_reset(user, operator)
    @user = user
    @operator = operator

    mail to: user.email, subject: "#{@operator.name} password reset", from: @operator.contact_email
    recipients = User.superadmins.all.map {|u| u.email }
  end

  def onboarding(user, password)
    @user = user
    @password = password

    mail to: @user.email, subject: "Welcome to #{user.operator.name}!", from: @user.operator.contact_email
  end
end