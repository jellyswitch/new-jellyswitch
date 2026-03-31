
class Billing::Leasing::SaveOfficeLease
  include Interactor

  delegate :office_lease, :operator, to: :context

  def call
    subscription = office_lease.subscription

    if office_lease.organization_id.present?
      subscribable = Organization.find(office_lease.organization_id)
    elsif office_lease.user_id.present?
      subscribable = User.find(office_lease.user_id)
    else
      context.fail!(message: 'Lease must have either an organization or a user')
      return
    end

    subscription.subscribable = subscribable
    subscription.billable = BillableFactory.for(subscription).billable
    subscription.start_date = office_lease.initial_invoice_date

    unless office_lease.end_date
      office_lease.end_date = office_lease.start_date + 1.year
    end

    office_lease.deposit_amount_in_cents ||= 0

    if office_lease.save
      context.office_lease = office_lease
    else
      context.fail!(message: 'Could not create lease')
    end
  end

  def rollback
    sub = context.office_lease.subscription
    context.office_lease.destroy
    sub.destroy
  end
end
