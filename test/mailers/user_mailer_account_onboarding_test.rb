require "test_helper"

# "Your account is ready" — the staff-triggered onboarding email for members
# whose account an admin created by hand. Admin-created accounts skip the
# self-signup confirmation + nudge emails, so this is the only thing that
# tells the person they have a login.
class UserMailerAccountOnboardingTest < ActionMailer::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @admin    = users(:cowork_tahoe_admin)
    @member   = users(:cowork_tahoe_member)      # in Sierra Nevada Alliance
    @loner    = users(:cowork_tahoe_non_member)  # organization: nil
  end

  test "addresses the member, names who set them up and their group, and explains code login" do
    mail = UserMailer.account_onboarding_email(@member, @operator, actor: @admin)

    assert_equal [@member.email], mail.to
    assert_equal "Your Cowork Tahoe account is ready", mail.subject
    assert_equal [@operator.contact_email], mail.reply_to

    body = mail.body.encoded
    assert_includes body, "Hi Tim,"
    assert_includes body, "#{@admin.name} at Cowork Tahoe set up an account for you as part of Sierra Nevada Alliance"
    assert_includes body, @member.email
    assert_includes body, "Email me a login code"
    assert_includes body, "Forgot password"
    # Operator fixture has store links → app download block is rendered.
    assert_includes body, @operator.ios_url
    # Transactional — no unsubscribe footer.
    refute_includes body, "Unsubscribe"
  end

  test "omits the group clause for a member with no organization" do
    mail = UserMailer.account_onboarding_email(@loner, @operator, actor: @admin)

    body = mail.body.encoded
    assert_includes body, "set up an account for you."
    refute_includes body, "as part of"
  end

  test "names the home location when one is given" do
    location = @operator.locations.first
    mail = UserMailer.account_onboarding_email(@member, @operator, actor: @admin, location: location)

    assert_includes mail.body.encoded, "Your home location is <strong>#{location.name}</strong>"
  end
end
