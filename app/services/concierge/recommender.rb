module Concierge
  # The scripted Concierge's recommender: turns a stated need into the right
  # product from the operator's REAL catalog. Self-serve, product-backed options
  # (day pass / bundle / membership) appear only when the operator actually
  # offers them; admin-handled options (rooms / office / a general question) are
  # always present and capture-only.
  class Recommender
    def initialize(operator:, location: nil)
      @operator = operator
      @location = location
    end

    def options
      [
        day_pass_option,
        bundle_option,
        membership_option,
        admin_option("day_office", "Private office for a day"),
        admin_option("conference_room", "My team needs to meet"),
        admin_option("office", "A long-term private office"),
        admin_option("question", "Just have a question"),
      ].compact
    end

    private

    def day_pass_types
      scope = @operator.day_pass_types.available.visible
      @location ? scope.where(location_id: @location.id) : scope
    end

    def plans
      scope = @operator.plans.for_individuals.nonzero
      @location ? scope.where(location_id: @location.id) : scope
    end

    def day_pass_option
      dpt = day_pass_types.where(quantity: 1).order(:amount_in_cents).first
      dpt && product_option("day_pass", "Drop in for a day", dpt)
    end

    def bundle_option
      dpt = day_pass_types.where("quantity > 1").order(:amount_in_cents).first
      dpt && product_option("day_pass_bundle", "Work for a few days", dpt)
    end

    def membership_option
      plan = plans.order(:amount_in_cents).first
      return nil unless plan
      {
        intent: "membership", label: "Somewhere to work, ongoing", self_serve: true,
        product: { id: plan.id, name: plan.name, price_cents: plan.amount_in_cents, interval: plan.interval },
      }
    end

    def product_option(intent, label, dpt)
      {
        intent: intent, label: label, self_serve: true,
        product: { id: dpt.id, name: dpt.name, price_cents: dpt.amount_in_cents, quantity: dpt.quantity },
      }
    end

    def admin_option(intent, label)
      { intent: intent, label: label, self_serve: false, product: nil }
    end
  end
end
