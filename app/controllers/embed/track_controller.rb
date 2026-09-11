# frozen_string_literal: true

module Embed
  # Page-view beacon from the concierge launcher on the operator's own site.
  # `navigator.sendBeacon` posts a text/plain JSON body (no CORS preflight);
  # we answer 204 no matter what — a beacon has no one to report errors to.
  class TrackController < ActionController::Base
    skip_before_action :verify_authenticity_token, raise: false

    def create
      operator = Operator.find_by(subdomain: params[:operator_subdomain].to_s.downcase)
      return head(:not_found) unless operator

      ua = request.user_agent.to_s
      return head(:no_content) if ua.blank? || DeviceDetector.new(ua).bot?

      payload = parse_payload
      SiteVisit.record(operator: operator, visitor_id: payload["v"], url: payload["u"],
                       referrer: payload["r"], user_agent: ua)
      head :no_content
    rescue => e
      Rails.logger.warn("Embed::TrackController: #{e.class}: #{e.message}")
      head :no_content
    end

    private

    def parse_payload
      raw = request.raw_post.to_s
      if raw.lstrip.start_with?("{")
        JSON.parse(raw).slice("v", "u", "r")
      else
        params.permit(:v, :u, :r).to_h
      end
    rescue JSON::ParserError
      {}
    end
  end
end
