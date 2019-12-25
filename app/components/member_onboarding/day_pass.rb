class MemberOnboarding::DayPass < ApplicationComponent
  include SignUpHelper
  def initialize(day_pass_types:, new_day_pass_path:)
    @day_pass_types = day_pass_types
    @new_day_pass_path = new_day_pass_path
  end

  private

  attr_reader :day_pass_types, :new_day_pass_path
end