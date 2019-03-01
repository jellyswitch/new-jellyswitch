class OperatorMailer < ApplicationMailer
  default from: 'Dave at Jellyswitch <dave@jellyswitch.com>'
  def new_demo_instance(user, operator)
    @user = user
    @operator = operator
    
    mail to: @user.email, subject: "Your Jellyswitch demo is ready"
  end
end