require "rails_helper"

RSpec.describe UserMailer, type: :mailer do
  let(:operator) { create(:operator) }
  let(:user) { create(:user, operator: operator) }

  before do
    ActionMailer::Base.default_url_options[:host] = "test.example.com"
  end

  describe "#password_reset" do
    before do
      user.create_reset_digest
    end

    context "when reset_token is passed explicitly (deliver_later fix)" do
      let(:mail) { described_class.password_reset(user, operator, user.reset_token) }

      it "generates a password reset email with a valid reset URL" do
        expect(mail.to).to eq([user.email])
        expect(mail.subject).to include("password reset")
      end

      it "includes a non-nil reset token in the URL" do
        body = mail.html_part&.body&.decoded || mail.body.decoded
        expect(body).to include("password_resets/")
        # The URL should NOT contain a nil or empty token segment
        expect(body).not_to match(%r{password_resets/\?})
        expect(body).not_to match(%r{password_resets//})
      end

      it "includes the user's email in the URL" do
        body = mail.html_part&.body&.decoded || mail.body.decoded
        expect(body).to include(CGI.escape(user.email))
      end

      it "includes the reset token value in the URL" do
        token = user.reset_token
        body = mail.html_part&.body&.decoded || mail.body.decoded
        expect(body).to include("password_resets/#{token}")
      end
    end

    context "when reset_token is NOT passed (simulates deliver_later deserialization)" do
      # This simulates what happens with deliver_later: the user is
      # deserialized from the database by Active Job, and the in-memory
      # reset_token attr_accessor is nil.
      let(:deserialized_user) { User.find(user.id) }

      it "has a nil reset_token on the deserialized user" do
        expect(deserialized_user.reset_token).to be_nil
      end

      it "raises a routing error due to nil token (the original bug)" do
        expect {
          described_class.password_reset(deserialized_user, operator).body
        }.to raise_error(ActionView::Template::Error)
      end
    end

    context "end-to-end: send_password_reset_email passes token correctly" do
      it "calls UserMailer.password_reset with the reset_token" do
        expect(UserMailer).to receive(:password_reset).with(
          user, operator, user.reset_token
        ).and_call_original

        user.send_password_reset_email
      end

      it "the reset_token argument is not nil" do
        expect(user.reset_token).not_to be_nil
      end
    end
  end
end
