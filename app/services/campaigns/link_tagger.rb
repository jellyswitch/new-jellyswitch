# frozen_string_literal: true

require "nokogiri"

module Campaigns
  # Appends UTM parameters to the links in a campaign email so the visit the
  # recipient makes is attributed to the email channel and to this campaign
  # (Attribution::Classifier → "email"; Data › Conversions "By Campaign").
  #
  #   Campaigns::LinkTagger.call(html, campaign_step: step, operator: operator)
  #
  # Rules: only absolute http(s) links; links that already carry any utm_
  # parameter are left alone (the author tagged them deliberately); mailto:,
  # tel:, anchors, and unsubscribe/one-click links are untouched. Runs before
  # SendGrid's click-tracking wrap, so the tags survive on the destination.
  class LinkTagger
    SKIP_PATH = %r{/unsubscribe|/email_preferences|/one_click}i

    def self.call(html, campaign_step:, operator:)
      new(html, campaign_step: campaign_step, operator: operator).call
    end

    def initialize(html, campaign_step:, operator:)
      @html = html.to_s
      @step = campaign_step
      @operator = operator
    end

    def call
      return @html if @html.blank? || !@html.include?("href")

      fragment = Nokogiri::HTML::DocumentFragment.parse(@html)
      fragment.css("a[href]").each do |a|
        tagged = tag(a["href"])
        a["href"] = tagged if tagged
      end
      fragment.to_html
    rescue => e
      Rails.logger.warn("Campaigns::LinkTagger skipped: #{e.class}: #{e.message}")
      @html
    end

    def params
      campaign = @step.campaign
      {
        "utm_source" => @operator.subdomain.presence || "jellyswitch",
        "utm_medium" => "email",
        "utm_campaign" => campaign&.name.to_s.strip.presence || "campaign-#{campaign&.id}",
        "utm_content" => "step-#{@step.position.to_i + 1}",
      }
    end

    private

    def tag(href)
      return nil if href.blank?
      uri = URI.parse(href.strip)
      return nil unless uri.is_a?(URI::HTTP) && uri.host.present?
      return nil if uri.path.to_s.match?(SKIP_PATH)

      existing = URI.decode_www_form(uri.query.to_s)
      return nil if existing.any? { |k, _| k.start_with?("utm_") }

      uri.query = URI.encode_www_form(existing + params.to_a)
      uri.to_s
    rescue URI::InvalidURIError
      nil
    end
  end
end
