require 'test_helper'

class PauseDeciderTest < ActiveSupport::TestCase
  # Current period end is on the 5th
  # I'm scheduled to pause
  # Today is the 4th: should return false
  # Today is the 5th: should return true
  # If today is the 5th and I'm not scheduled to pause, and I click pause at 11:59:45 pm, what SHOULD happen?
  
  # Stripe Invoice is created 1 hour after current period end, finalized an hour after that (within a few minutes)
  # Hourly: don't want a whole day to go by after someone pauses at 11pm or midnight

  # Current period is 12:01am
  # At midnight we run our cron job and it checks "today?" => true (works)
  # 
  
  test 'pauses when current_period_end is on the same day, but earlier' do
    travel_to Time.current.at_midday do
      assert PauseDecider.new(current_period_end: Time.current.beginning_of_day).should_pause?
    end
  end

  test 'pauses when current_period_end is on the same day, but later' do
    travel_to Time.current.at_midday do
      assert PauseDecider.new(current_period_end: Time.current.at_midday + 2.hours).should_pause?
    end
  end

  test 'pauses when current_period_end is at midnight this morning' do
    travel_to Time.current.beginning_of_day do
      assert PauseDecider.new(current_period_end: Time.current.beginning_of_day).should_pause?
    end
  end

  test 'does not pause when current_period_end is at midnight tomorrow' do
    travel_to Time.current.beginning_of_day do
      assert PauseDecider.new(current_period_end: Time.current.tomorrow.beginning_of_day).should_pause? == false
    end
  end

  test 'does not pause when current_period_end is at 11:59pm yesterday' do
    travel_to Time.current.beginning_of_day do
      assert PauseDecider.new(current_period_end: Time.current.beginning_of_day - 1.minute).should_pause? == false
    end
  end
end