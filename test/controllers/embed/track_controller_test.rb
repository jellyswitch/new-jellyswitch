require "test_helper"

class Embed::TrackControllerTest < ActionDispatch::IntegrationTest
  setup do
    @operator = operators(:cowork_tahoe)
    Rails.cache.clear
  end

  UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36".freeze

  def beacon(body, ua: UA)
    post embed_track_path(operator_subdomain: @operator.subdomain), params: body.to_json,
         headers: { "CONTENT_TYPE" => "text/plain", "HTTP_USER_AGENT" => ua }
  end

  test "a page view starts a session classified from its referrer, and a second view extends it" do
    assert_difference -> { SiteVisit.count } => 1 do
      beacon({ v: "abc123", u: "https://coworktahoe.com/pricing/?utm_source=instagram&utm_medium=social&utm_campaign=Fall", r: "https://l.instagram.com/" })
    end
    assert_response :no_content
    sv = SiteVisit.last
    assert_equal @operator, sv.operator
    assert_equal "social", sv.channel
    assert_equal "Fall", sv.utm_campaign
    assert_equal "coworktahoe.com", sv.host
    assert_equal 1, sv.page_views

    assert_no_difference -> { SiteVisit.count } do
      beacon({ v: "abc123", u: "https://coworktahoe.com/memberships/", r: "https://coworktahoe.com/pricing/" })
    end
    assert_equal 2, sv.reload.page_views
  end

  test "a new session that arrives from a search engine is organic; internal referrer is direct" do
    beacon({ v: "s1", u: "https://coworktahoe.com/", r: "https://www.google.com/" })
    assert_equal "organic_search", SiteVisit.last.channel

    beacon({ v: "s2", u: "https://coworktahoe.com/about/", r: "https://www.coworktahoe.com/" })
    assert_equal "direct", SiteVisit.last.channel
    assert_nil SiteVisit.last.referrer
  end

  test "bots and unknown operators record nothing" do
    assert_no_difference -> { SiteVisit.count } do
      beacon({ v: "b1", u: "https://coworktahoe.com/" }, ua: "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)")
      post embed_track_path(operator_subdomain: "nope"), params: { v: "x", u: "https://x.com/" }.to_json,
           headers: { "CONTENT_TYPE" => "text/plain", "HTTP_USER_AGENT" => UA }
      assert_response :not_found
    end
  end

  test "form-encoded fallback works and garbage never errors" do
    assert_difference -> { SiteVisit.count } => 1 do
      post embed_track_path(operator_subdomain: @operator.subdomain), params: { v: "f1", u: "https://coworktahoe.com/" },
           headers: { "HTTP_USER_AGENT" => UA }
    end
    post embed_track_path(operator_subdomain: @operator.subdomain), params: "{not json",
         headers: { "CONTENT_TYPE" => "text/plain", "HTTP_USER_AGENT" => UA }
    assert_response :no_content
  end
end
