
class UserMailer < ApplicationMailer
  helper ApplicationHelper
  helper LayoutHelper

  def password_reset(user, operator)
    @user = user
    @operator = operator
    mail to: user.email, subject: "#{@operator.name} password reset", from: 'Jellyswitch <noreply@jellyswitch.com>', reply_to: @operator.contact_email,
    'X-SMTPAPI' => {
      "filters" => {
        "clicktrack" => {
          "settings" => {
            "enable" => 0
          }
        },
        "opentrack" => {
          "settings" => {
            "enable" => 0
          }
        }
      }
    }.to_json
    recipients = User.superadmins.all.map {|u| u.email }
  end

  def event_registration(user, password, event)
    @user = user
    @password = password
    @event = event

    @host = ENV['ASSET_HOST']
    mail to: @user.email, subject: "You're all set for #{@event.title}!", from: "noreply@jellyswitch.com", reply_to: @user.operator.contact_email
  end

  def event_cancellation(user, event_name, operator)
    @user = user
    @event_name = event_name
    @operator = operator

    @host = ENV['ASSET_HOST']
    mail to: @user.email, subject: "Cancelled: #{@event_name}", from: "noreply@jellyswitch.com", reply_to: @operator.contact_email
  end
end
