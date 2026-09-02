module Showcase
  # Builds a Showcase tier from a catalog product. Bullets default to the
  # derived what's-included facts (the same config the system enforces at the
  # door and in billing — shown verbatim, never softened; 2026-08-27 plan §3);
  # an operator's own feature lines, when set, replace them entirely so every
  # bullet can be added or removed per product (2026-09-02).
  class ProductPresenter
    def initialize(product)
      @product = product
    end

    def tier
      {
        id: @product.id,
        kind: kind,
        name: @product.name,
        amount_in_cents: @product.amount_in_cents,
        price_label: price_label,
        featured: @product.featured,
        bullets: bullets,
      }
    end

    def bullets
      Array(@product.features).presence || default_bullets
    end

    # The automatic lines — what the product form prefills so an operator can
    # edit from them rather than retype them.
    def default_bullets
      @product.is_a?(Plan) ? plan_bullets : day_pass_bullets
    end

    private

    def kind
      @product.is_a?(Plan) ? "plan" : "day_pass_type"
    end

    def price_label
      dollars = format_price(@product.amount_in_cents)
      @product.is_a?(Plan) ? "#{dollars}/#{@product.interval.to_s.delete_suffix('ly')}" : dollars
    end

    def format_price(cents)
      whole = cents / 100
      cents % 100 == 0 ? "$#{whole}" : format("$%.2f", cents / 100.0)
    end

    def day_pass_bullets
      bullets = []
      bullets << "#{@product.quantity} day passes" if @product.quantity.to_i > 1
      if @product.included_meeting_room_minutes.to_i.positive?
        per_day = @product.quantity.to_i > 1 ? " per day" : ""
        bullets << "#{@product.included_meeting_room_minutes} min meeting room time#{per_day}"
      end
      bullets << if @product.always_allow_building_access
        "Anytime building access"
      else
        "Building access during open hours"
      end
      bullets
    end

    def plan_bullets
      bullets = []
      bullets << if @product.has_day_limit
        "#{@product.day_limit} days per month"
      else
        "Unlimited visits"
      end
      bullets << case @product.building_access_level
                 when "all_hours" then "24/7 building access"
                 when "business_hours" then "Building access during business hours"
                 else "No building access included"
                 end
      if @product.included_meeting_room_minutes.to_i.positive?
        bullets << "#{@product.included_meeting_room_minutes} min meeting room time per month"
      end
      bullets << "#{@product.credits} credits per month" if @product.credits.to_i.positive?
      if @product.commitment_interval.to_i.positive?
        bullets << "#{@product.commitment_interval}-month minimum commitment"
      end
      bullets
    end
  end
end
