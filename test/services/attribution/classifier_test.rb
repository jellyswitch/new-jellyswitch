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

class Attribution::ClassifierHostReferrerTest < ActiveSupport::TestCase
  test "a widget visit uses the host page's referrer passed as jsw_ref" do
    land = "https://tml.jellyswitch.com/embed/concierge?jsw_ref=#{CGI.escape('https://www.google.com/')}"
    r = Attribution::Classifier.call(referrer: "https://coworktahoe.com/", landing_page: land, surface: "widget")
    assert_equal "organic_search", r.channel
    assert_equal "google.com", r.referrer_domain
  end

  test "a widget visit with utm on the host page is the tagged channel" do
    land = "https://tml.jellyswitch.com/embed/concierge?utm_source=instagram&utm_medium=social&utm_campaign=Open+House"
    r = Attribution::Classifier.call(referrer: "https://coworktahoe.com/", landing_page: land,
                                     utm_source: "instagram", utm_medium: "social", utm_campaign: "Open House", surface: "widget")
    assert_equal "social", r.channel
    assert_equal "Open House", r.campaign
  end
end

class Attribution::ClassifierAccuracyTest < ActiveSupport::TestCase
  test "a referrer that is Jellyswitch itself is not a referral" do
    r = Attribution::Classifier.call(referrer: "https://tml.jellyswitch.com/home", landing_page: "https://tml.jellyswitch.com/login")
    assert_equal "direct", r.channel
    r = Attribution::Classifier.call(referrer: "https://untethered.jellyswitch.com/", landing_page: "https://tml.jellyswitch.com/")
    assert_equal "direct", r.channel
  end

  test "surface unknown is its own channel" do
    assert_equal "unknown", Attribution::Classifier.call(surface: "unknown").channel
  end
end
