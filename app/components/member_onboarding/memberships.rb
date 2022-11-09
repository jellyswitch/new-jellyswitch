class MemberOnboarding::Memberships < ApplicationComponent
  include SignUpHelper
  include ApplicationHelper

  attr_reader :plans, :location

  def initialize(plans:, location:)
    @plans = plans
    @location = location
  end

  def has_categories?
    location.operator.plan_categories.select do |plan_category|
      plan_category.plans.for_location(location).count.positive?
    end.count.positive?
  end
end