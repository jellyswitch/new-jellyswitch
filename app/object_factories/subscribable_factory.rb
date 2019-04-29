class SubscribableFactory
  def self.for(subscriber, subscription, start_day)
    if subscriber.out_of_band?
      if start_day.present?
        Subscribable::OutOfBandSpecifiedStartDay
      else
        Subscribable::OutOfBandDefaultStartDay
      end
    else
      if start_day.present?
        Subscribable::InBandSpecifiedStartDay
      else
        Subscribable::InBandDefaultStartDay
      end
    end.new(subscriber, subscription, start_day)
  end
end