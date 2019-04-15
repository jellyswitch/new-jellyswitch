class Billing::Leasing::BroadcastEvent
  delegate :office_lease, :operator, to: :context

  def call
    Jellyswitch::Events.publish(
      'billing.lease.create',
      office_lease_id: office_lease.id,
      operator_id: operator.id,
      start_date: office_lease.start_date
    )
  end
end
