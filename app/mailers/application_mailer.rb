
class ApplicationMailer < ActionMailer::Base
  default from: 'Jellyswitch <noreply@jellyswitch.com>',
          'X-SMTPAPI' => {
            "filters" => {
              "clicktrack" => {
                "settings" => {
                  "enable" => 0
                }
              }
            }
          }.to_json
  layout 'mailer'  

  
end
