class Billing::Leasing::InitializeRenewalOfficeLease
  include Interactor

  delegate :active_lease, to: :context

  def call
    office_lease = OfficeLease.new
    office_lease.build_subscription
    office_lease.subscription.build_plan
    office_lease.subscription.plan.location_id = active_lease.subscription.plan.location_id
    office_lease

    office_lease.office = active_lease.office
    office_lease.organization = active_lease.organization
    office_lease.location = active_lease.location
    office_lease.subscription.plan.amount_in_cents = active_lease.subscription.plan.amount_in_cents

    office_lease.start_date = office_lease.initial_invoice_date = active_lease.end_date
    office_lease.end_date = office_lease.start_date + 1.year

    context.renewal_lease = office_lease
  end

  def rollback
    context.office_lease.destroy
  end
end
