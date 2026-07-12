require "test_helper"

class ApplicationMailerSenderFallbackTest < ActionMailer::TestCase
  SENDER_IDENTITY_550 =
    "550 The from address does not match a verified Sender Identity. " \
    "Mail cannot be sent until this error is resolved."

  # Delivery agent that rejects attempts the way SendGrid rejects mail,
  # recording the headers of each attempt.
  class FakeSmtp
    cattr_accessor :attempts, :failures, :error_message

    def initialize(_settings = {}); end

    def deliver!(mail)
      self.class.attempts << { from: mail[:from].to_s, reply_to: mail.reply_to }
      if self.class.failures.positive?
        self.class.failures -= 1
        raise Net::SMTPFatalError, self.class.error_message
      end
    end
  end

  setup do
    @operator = operators(:cowork_tahoe)
    @user = users(:cowork_tahoe_member)
    @operator.stubs(:sender_from_address).returns("Tahoe Longhouse <hello@tahoelonghouse.com>")

    # email_confirmation's view links back into the app
    @previous_url_options = ActionMailer::Base.default_url_options
    ActionMailer::Base.default_url_options = { host: "app.lvh.me" }

    FakeSmtp.attempts = []
    FakeSmtp.failures = 0
    FakeSmtp.error_message = SENDER_IDENTITY_550
  end

  teardown do
    ActionMailer::Base.default_url_options = @previous_url_options
  end

  def build_mail
    mail = UserMailer.email_confirmation(@user, @operator, "tok123")
    mail.delivery_method(FakeSmtp)
    mail
  end

  test "unverified sender identity retries once from the platform sender" do
    FakeSmtp.failures = 1
    build_mail.deliver

    assert_equal 2, FakeSmtp.attempts.size
    assert_includes FakeSmtp.attempts[0][:from], "hello@tahoelonghouse.com"
    assert_includes FakeSmtp.attempts[1][:from], "noreply@jellyswitch.com"
  end

  test "delivers on the first attempt without interference when the sender is verified" do
    build_mail.deliver

    assert_equal 1, FakeSmtp.attempts.size
    assert_includes FakeSmtp.attempts[0][:from], "hello@tahoelonghouse.com"
  end

  test "keeps the brand reply_to on fallback" do
    FakeSmtp.failures = 1
    mail = build_mail
    mail.deliver

    assert_equal [@operator.contact_email], mail.reply_to
  end

  test "backfills reply_to with the original sender when none was set" do
    FakeSmtp.failures = 1
    mail = build_mail
    mail.reply_to = nil
    mail.deliver

    assert_equal ["hello@tahoelonghouse.com"], mail.reply_to
  end

  test "other SMTP fatal errors propagate untouched" do
    FakeSmtp.failures = 1
    FakeSmtp.error_message = "554 Message rejected"

    assert_raises(Net::SMTPFatalError) { build_mail.deliver }
    assert_equal 1, FakeSmtp.attempts.size
  end

  test "does not retry when the mail was already from the platform sender" do
    @operator.stubs(:sender_from_address).returns(ApplicationMailer::PLATFORM_FROM)
    FakeSmtp.failures = 1

    assert_raises(Net::SMTPFatalError) { build_mail.deliver }
    assert_equal 1, FakeSmtp.attempts.size
  end

  test "gives up rather than looping if the platform sender is also rejected" do
    FakeSmtp.failures = 2

    assert_raises(Net::SMTPFatalError) { build_mail.deliver }
    assert_equal 2, FakeSmtp.attempts.size
  end
end
