class OnboardingSidebar < ApplicationComponent
  include LayoutHelper

  def initialize(operator:, location:)
    @operator = operator
    @location = location
  end

  private

  attr_reader :operator, :location

  def billing_enabled?
    operator.subdomain != "southlakecoworking" && location.stripe_setup?
  end

  def show_day_pass_types?
    billing_enabled? && location.day_pass_types.count < 1
  end

  def show_rooms?
    billing_enabled? && location.rooms_enabled? && location.rooms.count < 1
  end

  def show_doors?
    billing_enabled? && location.door_integration_enabled? && location.doors.count < 1
  end

  def show_members?
    billing_enabled? && location.users.members.count < 1
  end
end