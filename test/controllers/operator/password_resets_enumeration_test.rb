require "test_helper"

# The forgot-password form answered "Email address not found." for an address
# with no account, and redirected somewhere different on success. Either signal
# lets anyone test whether a given person is a member here -- and since the
# address is also the login, it confirms half of a credential-stuffing pair.
# Every outcome must be indistinguishable from the outside.
class Operator::PasswordResetsEnumerationTest < ActionDispatch::IntegrationTest
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @user = users(:cowork_tahoe_member)
    host! "#{@operator.subdomain}.example.com"

    # ENV['HOST'] is unset in test, so mailer URL helpers have no host to build
    # from (the same reason spec/mailers/user_mailer_password_reset_spec.rb sets
    # this). Without it the reset email raises while rendering and #create
    # swallows it as a delivery failure -- which is correct behaviour, but it
    # would make the "known address actually sends" assertion vacuous.
    @original_mailer_host = ActionMailer::Base.default_url_options[:host]
    ActionMailer::Base.default_url_options[:host] = "example.com"
  end

  teardown do
    ActionMailer::Base.default_url_options[:host] = @original_mailer_host
  end

  def submit(email)
    post password_resets_path, params: { password_reset: { email: email } }, env: default_env
  end

  test "a known and an unknown address get the same response" do
    submit(@user.email)
    known = [response.status, response.location, flash[:success], flash[:error]]

    submit("nobody-#{SecureRandom.hex}@example.com")
    unknown = [response.status, response.location, flash[:success], flash[:error]]

    assert_equal known, unknown, "the response must not reveal whether the account exists"
  end

  test "an unknown address still reports success and sends nothing" do
    assert_no_difference "ActionMailer::Base.deliveries.size" do
      submit("nobody-#{SecureRandom.hex}@example.com")
    end

    assert_redirected_to root_path
    assert flash[:success].present?
    assert_nil flash[:error]
  end

  test "a known address still actually arms and sends the reset" do
    assert_difference "ActionMailer::Base.deliveries.size", 1 do
      submit(@user.email)
    end

    assert_redirected_to root_path
    @user.reload
    assert_not_nil @user.reset_digest
    assert_not_nil @user.reset_sent_at
  end

  test "a delivery failure is not a signal either" do
    submit("nobody-#{SecureRandom.hex}@example.com")
    unknown = [response.status, response.location, flash[:success], flash[:error]]

    User.any_instance.stubs(:send_password_reset_email).raises(Net::SMTPFatalError, "550 boom")
    submit(@user.email)

    assert_equal unknown, [response.status, response.location, flash[:success], flash[:error]]
  end

  test "a missing password_reset param does not 500" do
    post password_resets_path, env: default_env

    assert_response :redirect
  end

  test "a blank email does not 500 and reveals nothing" do
    submit("")

    assert_redirected_to root_path
    assert flash[:success].present?
  end
end
