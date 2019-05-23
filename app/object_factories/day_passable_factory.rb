class DayPassableFactory
  def self.for(day_pass, user)
    if user.out_of_band?
      DayPassable::OutOfBand
    else
      DayPassable::InBand
    end.new(day_pass, user)
  end
end