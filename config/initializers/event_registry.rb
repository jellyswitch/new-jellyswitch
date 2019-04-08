case ENV['EVENTS_CHANNEL_ADAPTER']
when 'sidekiq'
  Jellyswitch::Events.channel = Jellyswitch::Events::Channel::Sidekiq.instance
when 'active_support'
  Jellyswitch::Events.channel = Jellyswitch::Events::Channel::ActiveSupportNotification.new
else
  raise "Unknown Jellyswitch::Events::Channel adapter '#{Jellyswitch::Events.channel}'"
end

Jellyswitch::Events.register('billing.lease.create')
Jellyswitch::Events.subscribe('billing.lease.create', Billing::LeaseSync)
