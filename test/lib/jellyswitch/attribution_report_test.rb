require "test_helper"

module Jellyswitch
  class AttributionReportTest < ActiveSupport::TestCase
    setup do
      setup_initial_user_fixtures
      @operator = operators(:cowork_tahoe)
      @location = locations(:cowork_tahoe_location)
      @member = users(:cowork_tahoe_member)
      @other = users(:cowork_tahoe_non_member)
      @admin = users(:cowork_tahoe_admin)
      ActsAsTenant.current_tenant = @operator
    end

    teardown { ActsAsTenant.current_tenant = nil }

    def conv(kind:, user:, at: 2.days.ago, amount: 0, channel: "paid_search", campaign: nil, self_serve: true, surface: "web", subject: nil)
      Conversion.create!(operator: @operator, location: @location, user: user, kind: kind, occurred_at: at,
                         amount_cents: amount, channel: channel, campaign: campaign, self_serve: self_serve,
                         surface: surface, subject: subject, actor: (self_serve ? user : @admin))
    end

    test "funnel and by_channel roll up conversions for the location and period" do
      Ahoy::Visit.create!(visit_token: SecureRandom.uuid, visitor_token: "a", started_at: 1.day.ago,
                          landing_page: "https://tml.jellyswitch.com/?gclid=1")
      Ahoy::Visit.create!(visit_token: SecureRandom.uuid, visitor_token: "b", started_at: 1.day.ago,
                          landing_page: "https://tml.jellyswitch.com/signup", referrer: "https://www.google.com/")
      Ahoy::Visit.create!(visit_token: SecureRandom.uuid, visitor_token: "c", started_at: 1.day.ago,
                          landing_page: "https://other.jellyswitch.com/")

      conv(kind: "signup", user: @member, subject: @member)
      conv(kind: "tour_request", user: @other, channel: "organic_search")
      conv(kind: "day_pass", user: @member, amount: 3500, campaign: "Coworking-Lake-Tahoe")
      conv(kind: "membership", user: @member, amount: 25_000, at: 1.day.ago, self_serve: false)
      conv(kind: "day_pass", user: @other, amount: 4000, channel: "organic_search", at: 200.days.ago) # outside 90d

      report = Jellyswitch::AttributionReport.new(@location, period_days: 90, host: "tml.jellyswitch.com")

      f = report.funnel
      assert_equal 2, f[:visits]
      assert_equal 1, f[:leads]
      assert_equal 1, f[:signups]
      assert_equal 2, f[:purchases]
      assert_equal 285.0, f[:revenue]
      assert_equal 1, f[:first_purchases], "member's first purchase is in range; other's first was 200d ago"

      paid = report.by_channel["paid_search"]
      assert_equal 1, paid[:visits]
      assert_equal 1, paid[:signups]
      assert_equal 2, paid[:purchases]
      assert_equal 285.0, paid[:revenue]
      organic = report.by_channel["organic_search"]
      assert_equal 1, organic[:visits]
      assert_equal 1, organic[:leads]
      assert_equal 0, organic[:purchases]

      assert_equal 35.0, report.by_campaign["Coworking-Lake-Tahoe"][:revenue]

      ss = report.self_serve
      assert_equal 2, ss[:tracked_purchases]
      assert_equal 1, ss[:self_serve_purchases]
      assert_equal 50, ss[:self_serve_share]
      assert_equal 12, ss[:self_serve_revenue_share]
    end

    test "free rows are activity, not purchases; staff visits are excluded; referrals split by domain" do
      staff_visit = Ahoy::Visit.create!(visit_token: SecureRandom.uuid, visitor_token: "s", user: @admin, started_at: 1.day.ago,
                                        landing_page: "https://tml.jellyswitch.com/reports")
      Ahoy::Visit.create!(visit_token: SecureRandom.uuid, visitor_token: "r1", started_at: 1.day.ago,
                          landing_page: "https://tml.jellyswitch.com/", referrer: "https://coworktahoe.com/", referring_domain: "coworktahoe.com")
      Ahoy::Visit.create!(visit_token: SecureRandom.uuid, visitor_token: "r2", started_at: 1.day.ago,
                          landing_page: "https://tml.jellyswitch.com/", referrer: "https://tml.jellyswitch.com/home", referring_domain: "tml.jellyswitch.com")

      Conversion.create!(operator: @operator, location: @location, user: @member, kind: "room_reservation", occurred_at: 1.day.ago,
                         amount_cents: 0, channel: "referral", referrer_domain: "coworktahoe.com", surface: "app", self_serve: true, actor: @member)
      Conversion.create!(operator: @operator, location: @location, user: @member, kind: "day_pass", occurred_at: 1.day.ago,
                         amount_cents: 4000, channel: "referral", referrer_domain: "coworktahoe.com", surface: "web", self_serve: true, actor: @member)

      report = Jellyswitch::AttributionReport.new(@location, period_days: 90, host: "tml.jellyswitch.com")
      f = report.funnel
      assert_equal 2, f[:visits], "staff visit excluded"
      assert_equal 1, f[:purchases], "the free booking is not a purchase"
      assert_equal 40.0, f[:revenue]

      row = report.by_channel["referral:coworktahoe.com"]
      assert_equal 1, row[:visits]
      assert_equal 1, row[:purchases]
      assert_equal 40.0, row[:revenue]
      assert_equal 1, report.by_channel["direct"][:visits], "a self-referral is direct"
      assert_equal "Referral · coworktahoe.com", Jellyswitch::AttributionReport.channel_label("referral:coworktahoe.com")

      @member.update_columns(acquisition_channel: "referral", acquisition_referrer: "coworktahoe.com", original_location_id: @location.id)
      assert_includes report.people_for_channel("referral:coworktahoe.com"), @member
      assert_empty report.people_for_channel("referral:untethered.space")

      assert_equal 1, report.self_serve[:tracked_purchases], "self-serve share counts paid rows only"
    end

    test "website visits from the launcher beacon show in the funnel and by channel" do
      report = Jellyswitch::AttributionReport.new(@location, period_days: 90)
      assert_not report.site_tracker_active?

      SiteVisit.create!(operator: @operator, visitor_id: "a", started_at: 2.days.ago, last_seen_at: 2.days.ago,
                        channel: "organic_search", referring_domain: "google.com", host: "coworktahoe.com", page_views: 3)
      SiteVisit.create!(operator: @operator, visitor_id: "a", started_at: 1.day.ago, last_seen_at: 1.day.ago,
                        channel: "direct", host: "coworktahoe.com")
      SiteVisit.create!(operator: @operator, visitor_id: "b", started_at: 1.day.ago, last_seen_at: 1.day.ago,
                        channel: "referral", referring_domain: "yelp.com", host: "coworktahoe.com")
      SiteVisit.create!(operator: @operator, visitor_id: "old", started_at: 400.days.ago, last_seen_at: 400.days.ago, channel: "direct")

      report = Jellyswitch::AttributionReport.new(@location, period_days: 90)
      assert report.site_tracker_active?
      assert_equal 3, report.funnel[:site_visits]
      assert_equal 2, report.funnel[:site_visitors]
      assert_equal 1, report.by_channel["organic_search"][:site_visits]
      assert_equal 1, report.by_channel["referral:yelp.com"][:site_visits]
    end

    test "backfilled rows count toward channels but not the self-serve share" do
      conv(kind: "day_pass", user: @member, amount: 3500, surface: "backfill")
      report = Jellyswitch::AttributionReport.new(@location, period_days: 90)
      assert_equal 35.0, report.by_channel["paid_search"][:revenue]
      assert_equal 0, report.self_serve[:tracked_purchases]
    end
  end
end
