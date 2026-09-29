# Posts an admin feed card at the lease's location when an office lease is
# created, e.g. "Scott Lowe leased Office 300 · $698.98/mo". Org leases name
# the organization; the card's user is the org owner (or the individual
# lessee). Best-effort: a feed failure must never fail or roll back the lease.
class Billing::Leasing::CreateFeedItem
  include Interactor

  def call
    lease = context.office_lease
    return if lease.nil?

    user = lease.organization.present? ? lease.organization.owner : lease.user
    return if user.nil?

    lessee_name = lease.organization&.name.presence || user.name
    amount = ActionController::Base.helpers.number_to_currency(
      lease.subscription.plan.amount_in_cents / 100.0
    )

    FeedItemCreator.create_feed_item(
      lease.operator,
      lease.location || context.location,
      user,
      {
        text: "#{lessee_name} leased #{lease.office.name} · #{amount}/mo",
        type: "office_lease_created",
        office_lease_id: lease.id,
      }
    )
  rescue => e
    Rails.logger.error("Office lease feed item error: #{e.class}: #{e.message}")
    Honeybadger.notify(e)
  end
end
