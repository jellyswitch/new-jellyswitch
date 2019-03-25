class UserMailer < ApplicationMailer

  def password_reset(user, operator)
    @user = user
    @operator = operator

    mail to: user.email, subject: "#{@operator.name} password reset", from: @operator.contact_email
    recipients = User.superadmins.all.map {|u| u.email }
  end
end