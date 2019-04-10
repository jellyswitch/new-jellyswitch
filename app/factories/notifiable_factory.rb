class NotifiableFactory
  def self.for(notifiable)
    case notifiable.class
    when Subscription
      Notifiable::Subscription
    end.new(notifiable)
  end
end
