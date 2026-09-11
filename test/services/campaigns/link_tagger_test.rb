require "test_helper"

class Campaigns::LinkTaggerTest < ActiveSupport::TestCase
  setup do
    @operator = operators(:cowork_tahoe)
    @campaign = Campaign.create!(operator: @operator, name: "Fall Open House", segment: {})
    @step = CampaignStep.create!(campaign: @campaign, subject: "Hi", body: "x", position: 0)
  end

  def tag(html)
    Campaigns::LinkTagger.call(html, campaign_step: @step, operator: @operator)
  end

  test "appends utm source/medium/campaign/content to absolute links" do
    out = tag(%(<p>Come by! <a href="https://tml.jellyswitch.com/day_passes/new">Buy a pass</a></p>))
    href = Nokogiri::HTML::DocumentFragment.parse(out).at_css("a")["href"]
    q = URI.decode_www_form(URI.parse(href).query).to_h
    assert_equal "tml", q["utm_source"]
    assert_equal "email", q["utm_medium"]
    assert_equal "Fall Open House", q["utm_campaign"]
    assert_equal "step-1", q["utm_content"]
  end

  test "keeps existing query params and leaves author-tagged, mailto, anchor, and unsubscribe links alone" do
    html = %(<a href="https://coworktahoe.com/events?ref=x">a</a>
             <a href="https://coworktahoe.com/?utm_source=custom">b</a>
             <a href="mailto:hi@coworktahoe.com">c</a>
             <a href="#top">d</a>
             <a href="https://tml.jellyswitch.com/unsubscribe/abc">e</a>)
    hrefs = Nokogiri::HTML::DocumentFragment.parse(tag(html)).css("a").map { |a| a["href"] }
    assert_includes hrefs[0], "ref=x"
    assert_includes hrefs[0], "utm_medium=email"
    assert_equal "https://coworktahoe.com/?utm_source=custom", hrefs[1]
    assert_equal "mailto:hi@coworktahoe.com", hrefs[2]
    assert_equal "#top", hrefs[3]
    assert_equal "https://tml.jellyswitch.com/unsubscribe/abc", hrefs[4]
  end

  test "returns the body untouched when there are no links" do
    assert_equal "Just text", tag("Just text")
  end
end
