class AccessInstructions::DoorButtons < ApplicationComponent
  include ApplicationHelper
  
  def initialize(operator:, location:, mobile_app_request:, show_doors:, doors:)
    @operator = operator
    @location = location
    @mobile_app_request = mobile_app_request
    @show_doors = show_doors
    @doors = doors
  end

  private

  attr_reader :operator, :location, :mobile_app_request, :show_doors, :doors
end