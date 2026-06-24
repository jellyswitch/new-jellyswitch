require "rails_helper"

RSpec.describe UserMailer, "#login_code", type: :mailer do
  let(:operator) { create(:operator, subdomain: "mail-test") }
  let(:location) { create(:location, operator: operator) }
  let(:user) { create(:user, operator: operator, original_location: location, email: "m@example.com") }

  it "puts the 6-digit code in the subject and both body parts (for OS autofill)" do
    mail = UserMailer.login_code(user, operator, "123456")

    expect(mail.to).to eq(["m@example.com"])
    expect(mail.subject).to include("123456")
    expect(mail.subject).to match(/login code/i)

    body = mail.body.encoded
    expect(body).to include("123456")
    expect(body).to match(/login code/i)
    # 10-minute expiry communicated to the member.
    expect(body).to match(/10 minutes/i)
  end
end
