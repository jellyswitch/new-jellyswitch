class MemberOnboarding::Memberships < ApplicationComponent
  include SignUpHelper
  include ApplicationHelper

  attr_reader :plans, :location

  def initialize(plans:, location:)
    @plans = plans
    @location = location
  end
end