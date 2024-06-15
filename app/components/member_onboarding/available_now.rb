class MemberOnboarding::AvailableNow < ApplicationComponent
  include SignUpHelper
  include ApplicationHelper

  def initialize(available_rooms_now:)
    @available_rooms_now = available_rooms_now
  end

  private

  attr_reader :available_rooms_now
end
