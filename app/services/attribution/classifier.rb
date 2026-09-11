# frozen_string_literal: true

module Attribution
  # Turns the raw facts of a visit (referrer, landing page, UTM params) plus
  # the surface it arrived on into a channel. Pure function — no DB access —
  # so it is trivially testable and reusable by the backfill.
  #
  # Channel vocabulary (stable strings, shown in the Conversions report):
  #   paid_search, paid_social, organic_search, social, email, referral,
  #   direct, app, website (own-site widget), other_campaign
  class Classifier
    CHANNELS = %w[paid_search paid_social organic_search social email referral direct app website other_campaign].freeze

    SEARCH_ENGINES = %w[google. bing. duckduckgo. yahoo. ecosia. brave. baidu. yandex. ask.com aol.].freeze
    SOCIAL_DOMAINS = %w[facebook. fb.com instagram. linkedin. lnkd.in t.co twitter. x.com reddit. tiktok. youtube. youtu.be nextdoor. pinterest. threads.net snapchat.].freeze
    PAID_MEDIUMS   = %w[cpc ppc paid paidsearch paid_search sem].freeze
    SOCIAL_MEDIUMS = %w[social paidsocial paid_social].freeze
    EMAIL_MEDIUMS  = %w[email newsletter campaign_email].freeze

    Result = Struct.new(:channel, :source, :medium, :campaign, :referrer_domain, :landing_page, keyword_init: true)

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(referrer: nil, referring_domain: nil, landing_page: nil,
                   utm_source: nil, utm_medium: nil, utm_campaign: nil, surface: "web")
      @landing_page = landing_page.to_s
      # Widgets running on the operator's own site pass the HOST page's
      # referrer along as jsw_ref (the iframe's own referrer is just the
      # operator's site, which says nothing about where the person came from).
      host_ref = host_page_referrer
      @referrer = host_ref.presence || referrer.to_s
      @referring_domain = (host_ref.present? ? domain_of(host_ref) : (referring_domain.presence || domain_of(@referrer))).to_s.downcase.delete_prefix("www.")
      @utm_source = utm_source.to_s.downcase.presence
      @utm_medium = utm_medium.to_s.downcase.presence
      @utm_campaign = utm_campaign.presence
      @surface = surface.to_s
    end

    def call
      channel, source, medium = classify
      Result.new(
        channel: channel,
        source: source,
        medium: medium,
        campaign: @utm_campaign,
        referrer_domain: @referring_domain.presence,
        landing_page: @landing_page.presence&.first(255),
      )
    end

    private

    def classify
      # 1. Explicit tagging wins.
      if @utm_medium || @utm_source
        return ["paid_search", @utm_source || "paid", @utm_medium] if PAID_MEDIUMS.include?(@utm_medium)
        return ["paid_social", @utm_source || "social", @utm_medium] if SOCIAL_MEDIUMS.include?(@utm_medium) && paid_hint?
        return ["social", @utm_source || "social", @utm_medium] if SOCIAL_MEDIUMS.include?(@utm_medium)
        return ["email", @utm_source || "email", @utm_medium] if EMAIL_MEDIUMS.include?(@utm_medium)
        return ["other_campaign", @utm_source, @utm_medium]
      end

      # 2. Ad click IDs on the landing page.
      return ["paid_search", "google", "cpc"] if landing_has?(/[?&](gclid|gbraid|wbraid)=/)
      return ["paid_search", "bing", "cpc"] if landing_has?(/[?&]msclkid=/)
      return ["paid_social", "facebook", "paid_social"] if landing_has?(/[?&]fbclid=/) && paid_hint?
      return ["social", "facebook", "social"] if landing_has?(/[?&]fbclid=/)
      return ["paid_social", "tiktok", "paid_social"] if landing_has?(/[?&]ttclid=/)

      # 3. Referrer.
      if @referring_domain.present?
        return ["organic_search", @referring_domain, "organic"] if SEARCH_ENGINES.any? { |d| @referring_domain.include?(d) }
        return ["social", @referring_domain, "social"] if SOCIAL_DOMAINS.any? { |d| @referring_domain.include?(d) }
        return ["referral", @referring_domain, "referral"]
      end

      # 4. Nothing to go on.
      case @surface
      when "app" then ["app", "mobile_app", nil]
      when "widget" then ["website", "website", nil]
      else ["direct", nil, nil]
      end
    end

    def paid_hint?
      @utm_medium.to_s.include?("paid") || @utm_campaign.to_s.downcase.include?("ad")
    end

    def landing_has?(regex)
      @landing_page.match?(regex)
    end

    def host_page_referrer
      return nil unless @landing_page.include?("jsw_ref=")
      query = URI.parse(@landing_page).query.to_s
      URI.decode_www_form(query).to_h["jsw_ref"].presence
    rescue URI::InvalidURIError
      nil
    end

    def domain_of(url)
      return nil if url.blank?
      URI.parse(url).host
    rescue URI::InvalidURIError
      nil
    end
  end
end
