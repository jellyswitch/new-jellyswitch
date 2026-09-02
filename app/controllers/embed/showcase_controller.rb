module Embed
  # Serves the Showcase as JavaScript that renders inline DOM into the host
  # page (ADR 0027: SEO attribution — content must be on-page, so no iframe).
  # Read-only: purchases go through the existing concierge checkout.
  class ShowcaseController < ActionController::Base
    layout false
    # Cross-origin <script> embedding is this endpoint's entire purpose —
    # Rails' same-origin JS guard must not block it. Read-only: no state
    # changes happen here (purchases go through the checkout's own perimeter).
    skip_forgery_protection

    before_action :load_operator

    PRODUCT_MODES = %w[day_passes memberships all cards].freeze

    def widget
      expires_in 5.minutes, public: true
      return render_noop("Showcase is not enabled for #{@operator.subdomain}") unless @operator.showcase_enabled?

      visible = @operator.locations.where(visible: true).order(:name)
      @location = @operator.locations.find_by(id: params[:location_id])
      # Pinned-only at multi-location operators (plan §4): never guess or
      # merge catalogs — prices live on location pages. Render the setup
      # nudge with per-location snippet lines instead.
      if @location.nil? && visible.count > 1
        @nudge_locations = visible
        return render :nudge
      end
      @location ||= visible.first
      return render_noop("No visible location for #{@operator.subdomain}") unless @location

      @mode = PRODUCT_MODES.include?(params[:products]) ? params[:products] : "all"
      @sections = build_sections
      render :widget
    end

    private

    def load_operator
      @operator = Operator.find_by!(subdomain: params[:operator_subdomain])
    end

    def render_noop(message)
      render js: "/* #{message} */"
    end

    def build_sections
      sections = []
      if %w[day_passes all].include?(@mode)
        sections << { key: "day_passes", title: "Day Passes", tiers: day_pass_tiers(:standard) + card_tiers("day_passes") }
        # Day Office types and their packs are one family, regular day passes
        # and their packs another — never interleaved by price (2026-09-02).
        sections << { key: "day_offices", title: "Day Offices", tiers: day_pass_tiers(:day_office) }
      end
      if %w[memberships all].include?(@mode)
        sections << { key: "memberships", title: "Memberships", tiers: membership_tiers + card_tiers("memberships") }
      end
      sections << { key: "cards", title: nil, tiers: card_tiers("standalone") } if @mode == "cards"
      sections.reject { |s| s[:tiers].empty? }
    end

    def day_pass_tiers(kind)
      DayPassType.where(operator: @operator, kind: kind).available.visible
                 .for_location(@location)
                 .order(:display_order, :amount_in_cents)
                 .map { |p| Showcase::ProductPresenter.new(p).tier.merge(cta: checkout_url(day_pass_type_id: p.id)) }
    end

    def membership_tiers
      # for_individuals already folds in available+visible; Plan.for_location
      # is deliberately strict (no nil catch-all), matching the recommender.
      Plan.where(operator: @operator).for_individuals.nonzero
          .for_location(@location)
          .order(:display_order, :amount_in_cents)
          .map { |p| Showcase::ProductPresenter.new(p).tier.merge(cta: checkout_url(plan_id: p.id)) }
    end

    def card_tiers(slot)
      ShowcaseCard.where(operator: @operator, location: @location).for_slot(slot).map do |c|
        {
          id: "card-#{c.id}", kind: "card", name: c.label, price_label: c.price_text,
          featured: false, bullets: [c.description].compact_blank, cta: c.url, external: true,
        }
      end
    end

    def checkout_url(extra)
      embed_concierge_checkout_url(
        { operator_subdomain: @operator.subdomain, host: request.host_with_port,
          location_id: @location.id }.merge(extra),
      )
    end
  end
end
