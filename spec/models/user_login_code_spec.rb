require "rails_helper"

# Passwordless Login Code (OTP) — ADR 0016. The code is a single-use 6-digit
# number, stored only as a bcrypt digest (mirrors reset_digest), valid 10 min,
# burned after 5 wrong guesses, and a successful verify confirms the email.
RSpec.describe User, "login code (OTP)", type: :model do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:user) do
    create(:user, operator: operator, original_location: location,
                  role: User::UNASSIGNED, email_confirmed: false)
  end

  describe "#generate_login_code" do
    it "returns a 6-digit numeric code and stores only its digest" do
      code = user.generate_login_code
      expect(code).to match(/\A\d{6}\z/)
      expect(user.login_code_digest).to be_present
      expect(user.login_code_digest).not_to eq(code) # never store plaintext
      expect(user.login_code_sent_at).to be_within(5.seconds).of(Time.current)
      expect(user.login_code_attempts).to eq(0)
    end

    it "overwrites (invalidates) a prior code — only one active at a time" do
      first = user.generate_login_code
      user.generate_login_code
      expect(user.verify_login_code(first)).to be(false)
    end
  end

  describe "#verify_login_code" do
    it "accepts the correct code and consumes it (single-use)" do
      code = user.generate_login_code
      expect(user.verify_login_code(code)).to be(true)
      expect(user.login_code_digest).to be_nil
      # second use of the same code fails (consumed)
      expect(user.verify_login_code(code)).to be(false)
    end

    it "confirms the email as a side-effect of a successful verify" do
      code = user.generate_login_code
      expect { user.verify_login_code(code) }
        .to change { user.reload.email_confirmed? }.from(false).to(true)
    end

    it "rejects a wrong code and counts the attempt" do
      user.generate_login_code
      expect(user.verify_login_code("000000")).to be(false)
      expect(user.reload.login_code_attempts).to eq(1)
    end

    it "burns the code after 5 wrong guesses (must request a new one)" do
      code = user.generate_login_code
      5.times { user.verify_login_code("000000") }
      expect(user.reload.login_code_digest).to be_nil
      # even the correct code no longer works — it was burned
      expect(user.verify_login_code(code)).to be(false)
    end

    it "rejects an expired code" do
      code = user.generate_login_code
      user.update_columns(login_code_sent_at: 11.minutes.ago)
      expect(user.verify_login_code(code)).to be(false)
    end

    it "rejects when there is no active code" do
      expect(user.verify_login_code("123456")).to be(false)
    end
  end

  describe "#login_code_expired?" do
    it "is true with no code and true past the 10-minute window" do
      expect(user.login_code_expired?).to be(true)
      user.generate_login_code
      expect(user.login_code_expired?).to be(false)
      user.update_columns(login_code_sent_at: 10.minutes.ago - 1.second)
      expect(user.login_code_expired?).to be(true)
    end
  end
end
