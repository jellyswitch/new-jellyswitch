class Billing::Leasing::UpdateEndDateToPeriodEnd
  include Interactor

  delegate :office_lease, to: :context

  def call
    period_end = office_lease.subscription.current_period_end
    unless period_end
      context.fail!(message: "Cannot determine subscription period end date.")
      return
    end
    context.old_end_date = office_lease.end_date
    office_lease.update(end_date: period_end)
  end

  def rollback
    office_lease.update(end_date: context.old_end_date)
  end
end
