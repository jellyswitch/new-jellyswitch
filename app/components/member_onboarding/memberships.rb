class MemberOnboarding::Memberships < ApplicationComponent
  include SignUpHelper
  include ApplicationHelper

  def initialize(plans:)
    @plans = plans
  end

  private

  attr_reader :plans
end