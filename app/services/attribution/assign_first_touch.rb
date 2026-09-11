# frozen_string_literal: true

module Attribution
  # Stamps a user's first-touch attribution from their earliest known visit.
  # Ahoy only links a visit to a user once they log in, so we hop from the
  # first linked visit to the earliest visit sharing the same persistent
  # visitor cookie — that's the true first touch on Jellyswitch.
  #
  # Idempotent: once acquired_at is set the user is never re-classified
  # (first touch is frozen by definition). Pass force: true to recompute.
  class AssignFirstTouch
    def self.call(user, fallback_visit: nil, surface: "web", force: false)
      new(user, fallback_visit: fallback_visit, surface: surface, force: force).call
    end

    def initialize(user, fallback_visit:, surface:, force:)
      @user = user
      @fallback_visit = fallback_visit
      @surface = surface
      @force = force
    end

    def call
      return @user if @user.acquired_at.present? && !@force

      visit = first_visit
      result = Classifier.call(
        referrer: visit&.referrer,
        referring_domain: visit&.referring_domain,
        landing_page: visit&.landing_page,
        utm_source: visit&.utm_source,
        utm_medium: visit&.utm_medium,
        utm_campaign: visit&.utm_campaign,
        # No visit at all (imported, staff-added, pre-tracking): we don't know.
        # App signups and widget leads keep their surface — those tell us
        # where the person came in even without a visit row.
        surface: visit ? surface_for(visit) : (%w[app widget].include?(@surface) ? @surface : "unknown"),
      )

      @user.update_columns(
        acquisition_channel: result.channel,
        acquisition_source: result.source&.first(255),
        acquisition_medium: result.medium&.first(255),
        acquisition_campaign: result.campaign&.first(255),
        acquisition_referrer: result.referrer_domain&.first(255),
        acquisition_landing_page: result.landing_page,
        acquisition_visit_id: visit&.id,
        acquired_at: visit&.started_at || @user.created_at || Time.current,
      )
      @user
    end

    private

    def first_visit
      linked = Ahoy::Visit.where(user_id: @user.id).order(:started_at).first
      linked ||= @fallback_visit
      return nil unless linked

      if linked.visitor_token.present?
        Ahoy::Visit.where(visitor_token: linked.visitor_token).order(:started_at).first || linked
      else
        linked
      end
    end

    def surface_for(visit)
      visit.user_agent.to_s.include?("Jellyswitch") ? "app" : @surface
    end
  end
end
