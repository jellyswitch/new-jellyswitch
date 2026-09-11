require "test_helper"

class UserMailerCampaignEmailTest < ActionMailer::TestCase
  setup do
    setup_initial_user_fixtures
    @operator = operators(:cowork_tahoe)
    @user = users(:cowork_tahoe_member)
    @campaign = Campaign.create!(operator: @operator, name: "Winter Promo", segment: {})
    @step = CampaignStep.create!(campaign: @campaign, subject: "Hello {{first_name}}",
                                 body: %(<p>Hi {{first_name}}, <a href="https://tml.jellyswitch.com/plans">see plans</a></p>),
                                 position: 0)
  end

  test "campaign email links are utm-tagged with the campaign name" do
    mail = UserMailer.campaign_email(@user, @operator, @step)
    body = mail.html_part ? mail.html_part.body.to_s : mail.body.to_s
    assert_includes body, "utm_medium=email"
    assert_includes body, "utm_campaign=Winter+Promo"
    assert_includes body, "utm_source=#{@operator.subdomain}"
  end
end
