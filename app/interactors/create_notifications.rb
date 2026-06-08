
class CreateNotifications
  include Interactor

  delegate :notifiable, to: :context

  def call
    # No notifiable means an upstream step intentionally produced nothing to
    # announce (e.g. WeeklyUpdates::Save hit an already-existing update and
    # skipped it for idempotency). Nothing to notify.
    return if notifiable.blank?

    NotifiableFactory.for(notifiable).notify
  end

  def rollback
    context.notifiable&.destroy
  end
end
