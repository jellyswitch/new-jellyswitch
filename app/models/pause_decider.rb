class PauseDecider
  attr_reader :current_period_end
  def initialize(current_period_end:)
    @current_period_end = current_period_end.in_time_zone
  end

  def should_pause?
    current_period_end.today?
  end
end