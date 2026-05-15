require "rails_helper"

RSpec.describe ApplicationMailer, type: :mailer do
  describe "after_action :log_email_sent" do
    let(:operator) { create(:operator) }
    let(:user) { create(:user, operator: operator, email: "test@example.com") }

    before do
      ActionMailer::Base.default_url_options[:host] = "test.example.com"
    end

    it "logs an :email_sent Activity for emails to a known user" do
      user # force creation so the signup Activity doesn't fall inside the expect block

      expect {
        UserMailer.password_reset(user, operator, "abc123").deliver_now
      }.to change(Activity.where(kind: "email_sent"), :count).by(1)

      activity = Activity.where(kind: "email_sent").last
      expect(activity.user).to eq(user)
      expect(activity.operator).to eq(operator)
    end

    it "denormalizes mailer name, action, recipient, and subject into payload" do
      user
      UserMailer.password_reset(user, operator, "abc123").deliver_now

      payload = Activity.where(kind: "email_sent").last.payload
      expect(payload["mailer"]).to eq("UserMailer")
      expect(payload["action"]).to eq("password_reset")
      expect(payload["to"]).to eq(user.email)
      expect(payload["subject"]).to include("password reset")
    end

    it "silently skips when recipient email matches no known user" do
      user # ensure the existing user's signup Activity is outside the expect
      stranger = build(:user, email: "stranger-#{SecureRandom.hex(4)}@nowhere.test")

      expect {
        UserMailer.password_reset(stranger, operator, "abc123").deliver_now
      }.not_to change(Activity.where(kind: "email_sent"), :count)
    end

    it "does not raise even if Activity.log itself errors (failure is best-effort)" do
      user
      allow(Activity).to receive(:log).and_raise(StandardError.new("oops"))

      expect {
        UserMailer.password_reset(user, operator, "abc123").deliver_now
      }.not_to raise_error
    end
  end
end
