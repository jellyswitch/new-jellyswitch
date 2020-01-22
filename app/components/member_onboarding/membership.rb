class MemberOnboarding::Membership < ApplicationComponent
  include PlansHelper

  def initialize(plan:)
    @plan = plan
  end

  private

  attr_reader :plan
end