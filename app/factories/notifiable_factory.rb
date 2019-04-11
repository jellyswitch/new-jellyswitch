class NotifiableFactory
  def self.for(notifiable)
    case notifiable.class.name
    when 'Subscription'
      Notifiable::Subscription
    end.new(notifiable)
  end
end
