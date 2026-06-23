
class Billing::Leasing::UpdateEndDate
  include Interactor

  delegate :office_lease, to: :context

  def call
    # "Terminate now": end the lease on the subscription's cancellation date
    # when we have one, otherwise today. The fallback matters for a "zombie"
    # lease whose subscription was already cancelled (member self-cancel /
    # downgrade / failed payment) — ended_at can be nil there, and the old
    # hard-fail left admins with an un-terminable lease.
    ended_at = office_lease.subscription&.ended_at || Date.current
    context.old_end_date = office_lease.end_date
    office_lease.update(end_date: ended_at)
  end

  def rollback
    office_lease.update(end_date: context.old_end_date)
  end
end