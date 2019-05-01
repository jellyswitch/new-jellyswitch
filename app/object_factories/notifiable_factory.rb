class NotifiableFactory
  def self.for(notifiable)
    case notifiable.class.name
    when 'Subscription'
      Notifiable::Subscription
    when 'DayPass'
      Notifiable::DayPass
    end.new(notifiable)
  end
end
