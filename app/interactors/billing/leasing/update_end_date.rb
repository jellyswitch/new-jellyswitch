
class Billing::Leasing::UpdateEndDate
  include Interactor

  delegate :office_lease, to: :context

  def call
    ended_at = office_lease.subscription.ended_at
    unless ended_at
      context.fail!(message: "Cannot determine subscription end date.")
      return
    end
    context.old_end_date = office_lease.end_date
    office_lease.update(end_date: ended_at)
  end

  def rollback
    office_lease.update(end_date: context.old_end_date)
  end
end