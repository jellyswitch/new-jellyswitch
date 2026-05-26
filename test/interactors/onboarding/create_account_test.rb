require "test_helper"

# Regression coverage for the operator-onboarding password leak: before this
# change, `Onboarding::CreateAdmin` hard-coded `password: "foobar"` for every
# new workspace owner. Anyone who knew the convention could log in as them
# until they noticed and changed the password. These tests assert (a) the
# call refuses to create an admin when no password is supplied, and (b) when
# a password IS supplied, the resulting user authenticates with it (not
# "foobar").
class Onboarding::CreateAccountTest < ActiveSupport::TestCase
  test "fails when no password is provided" do
    result = Onboarding::CreateAccount.call(
      email: "no-password-#{SecureRandom.hex(4)}@example.com",
    )

    refute result.success?, "expected CreateAccount to fail without a password"
  end

  test "creates an admin whose password is the one supplied, not 'foobar'" do
    email    = "ok-#{SecureRandom.hex(4)}@example.com"
    password = "correct-horse-battery-staple"

    result = Onboarding::CreateAccount.call(
      email:                 email,
      password:              password,
      password_confirmation: password,
    )

    assert result.success?, "CreateAccount failed: #{result.message}"
    assert result.user.authenticate(password),
      "new admin should authenticate with the supplied password"
    refute result.user.authenticate("foobar"),
      "new admin must NOT authenticate with the old hard-coded 'foobar' password"
  end
end
