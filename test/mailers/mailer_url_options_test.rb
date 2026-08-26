require "test_helper"

# Guards the class of bug where an emailed link is wrong or unbuildable and no
# test notices.
#
# Two real incidents this is pinned to:
#
#   1. ENV['HOST'] is unset in test, so application.rb left default_url_options
#      as {host: nil} and every *_url helper in a mailer template raised
#      "Missing host to link to!". Templates only rendered in tests that set the
#      host by hand, so an unbuilt link elsewhere shipped green.
#   2. HostValidator defined its own default_url_options returning a bare
#      {host: ...}. An instance method fully replaces the config hash, so it
#      silently discarded `protocol: 'https'` and FeedItemsMailer kept emitting
#      http:// links after every other mailer was fixed.
class MailerUrlOptionsTest < ActiveSupport::TestCase
  # Mailers whose templates call *_url helpers, with a builder for valid args.
  # Add a row when you add a mailer that links anywhere.
  def rendering_cases
    operator = operators(:cowork_tahoe)
    user = users(:cowork_tahoe_member)

    [
      ["UserMailer#password_reset", -> {
        user.create_reset_digest
        UserMailer.password_reset(user, operator, user.reset_token)
      }],
      ["UserMailer#email_confirmation", -> {
        user.generate_confirmation_token
        UserMailer.email_confirmation(user, operator, user.raw_confirmation_token)
      }],
    ]
  end

  test "the test environment gives mailers a host to build URLs from" do
    assert ActionMailer::Base.default_url_options[:host].present?,
           "without a host every *_url helper in a mailer template raises, and " \
           "mailer tests silently stop covering their links"
  end

  # The invariant: overriding default_url_options is fine, discarding what the
  # app configured is not.
  test "no mailer drops the app-level url options" do
    # The test env does not eager load, so descendants is empty until the mailer
    # classes are actually referenced -- without this the guard passes vacuously
    # and protects nothing.
    Rails.application.eager_load!

    base = ActionMailer::Base.default_url_options
    overriders = ApplicationMailer.descendants.select do |klass|
      klass.instance_method(:default_url_options).owner != ActionMailer::Base &&
        klass.instance_method(:default_url_options).owner != ActionDispatch::Routing::UrlFor
    end

    overriders.each do |klass|
      mailer = klass.new
      mailer.instance_variable_set(:@operator, operators(:cowork_tahoe))
      options = mailer.send(:default_url_options)

      missing = base.keys - options.keys
      assert_empty missing,
                   "#{klass} overrides default_url_options and drops #{missing.inspect} " \
                   "from the app-level config -- merge onto `super` instead of returning a bare hash"
    end

    assert_operator overriders.size, :>=, 1,
                    "expected to find at least one mailer overriding default_url_options " \
                    "(FeedItemsMailer via HostValidator) -- if this is empty the guard is vacuous"
  end

  test "every URL in a rendered mailer is absolute and carries a host" do
    rendering_cases.each do |label, build|
      mail = build.call
      body = rendered_body(mail)

      urls = body.scan(%r{https?://[^\s"'<>\)]+}).uniq
      assert urls.any?, "#{label} rendered no URLs at all -- did the template stop linking, or did rendering fail?"

      urls.each do |url|
        parsed = URI.parse(url)
        assert parsed.host.present?, "#{label} emitted a URL with no host: #{url}"
        assert parsed.host.include?("."), "#{label} emitted a suspicious host (#{parsed.host}) in #{url}"
        assert_not parsed.host.start_with?("."), "#{label} emitted a URL with an empty subdomain: #{url}"
      end
    end
  end

  test "rendering a mailer template never raises for a missing host" do
    rendering_cases.each do |label, build|
      begin
        mail = build.call
        assert rendered_body(mail).present?, "#{label} rendered an empty body"
      rescue ActionView::Template::Error => e
        flunk "#{label} failed to render: #{e.cause&.message || e.message}"
      end
    end
  end

  private

  # Multipart mail keeps its content in the parts; Mail::Message#body is empty
  # for them, so reading only `body.decoded` looks like "rendered nothing".
  def rendered_body(mail)
    [mail.html_part&.body&.decoded, mail.text_part&.body&.decoded, mail.body.decoded].compact.join("\n")
  end
end
