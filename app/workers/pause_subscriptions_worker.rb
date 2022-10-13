class PauseSubscriptionsWorker
  include Sidekiq::Worker
  sidekiq_options retry: 0, queue: 'default'

  def perform
    PauseMemberships.call
  end
end