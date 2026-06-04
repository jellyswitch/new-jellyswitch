
class SendNotificationsJob < ApplicationJob
  queue_as :default

  # Defense in depth: any notifiable (Activity, Reservation, FeedbackReply,
  # User, ...) can be deleted between enqueue and execution. If the record is
  # gone there's nothing to notify about, so discard quietly instead of
  # retrying ~25x and alerting. Logged so discards stay observable.
  discard_on ActiveJob::DeserializationError do |_job, error|
    Rails.logger.warn("[SendNotificationsJob] discarded — notifiable no longer exists: #{error.message}")
  end

  def perform(notifiable, notifiable_type = nil)
    NotifiableFactory.for(notifiable, notifiable_type).notify
  end
end
