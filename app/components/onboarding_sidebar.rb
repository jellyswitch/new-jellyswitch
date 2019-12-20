class OnboardingSidebar < ApplicationComponent
  include LayoutHelper

  def initialize(operator:, location:)
    @operator = operator
    @location = location
  end

  private

  attr_reader :operator, :location

  def billing_enabled?
    operator.production? && operator.subdomain != "southlakecoworking"
  end
end