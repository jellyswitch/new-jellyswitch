require "test_helper"

class Attribution::ClassifierTest < ActiveSupport::TestCase
  def classify(**kw)
    Attribution::Classifier.call(**kw)
  end

  test "utm medium cpc is paid search with the utm source" do
    r = classify(utm_source: "google", utm_medium: "cpc", utm_campaign: "Coworking-Lake-Tahoe")
    assert_equal "paid_search", r.channel
    assert_equal "google", r.source
    assert_equal "Coworking-Lake-Tahoe", r.campaign
  end

  test "utm medium email is the email channel" do
    r = classify(utm_source: "jellyswitch", utm_medium: "email", utm_campaign: "Day pass nurture")
    assert_equal "email", r.channel
    assert_equal "Day pass nurture", r.campaign
  end

  test "gclid on the landing page is paid search even with no referrer" do
    r = classify(landing_page: "https://untethered.jellyswitch.com/signup?gclid=abc123")
    assert_equal "paid_search", r.channel
    assert_equal "google", r.source
  end

  test "search engine referrer is organic search" do
    r = classify(referrer: "https://www.google.com/", landing_page: "https://tml.jellyswitch.com/")
    assert_equal "organic_search", r.channel
    assert_equal "google.com", r.referrer_domain
  end

  test "social referrer is social" do
    r = classify(referrer: "https://l.instagram.com/?u=x")
    assert_equal "social", r.channel
  end

  test "other referrer is a referral keyed by domain" do
    r = classify(referrer: "https://www.untethered.space/coworking/")
    assert_equal "referral", r.channel
    assert_equal "untethered.space", r.referrer_domain
  end

  test "no signal defaults by surface" do
    assert_equal "direct", classify.channel
    assert_equal "app", classify(surface: "app").channel
    assert_equal "website", classify(surface: "widget").channel
  end
end
