
class Billing::Invoices::Refunds::Save
  include Interactor
  delegate :operator, :invoice, :location, to: :context

  def call
    unless invoice.cancel
      context.fail!(message: 'This invoice could not be refunded — it may already be refunded.')
      return
    end

    # The refund is committed the moment invoice.cancel returns true (Stripe
    # refund + status flip). The feed-item write is a best-effort side effect:
    # a feed/search-index failure must never flip a committed refund to
    # "failed" or page Honeybadger. See ADR 0014.
    create_refund_feed_item
  end

  private

  def create_refund_feed_item
    billable = invoice.billable
    return if billable.is_a?(Organization) # mirror FeedItemCreator's org guard

    FeedItemCreator.create_feed_item(
      operator,
      invoice.location || location,
      billable,
      { type: 'refund', invoice_id: invoice.id },
    )
  rescue => e
    Rails.logger.warn(
      "[Refunds::Save] post-refund feed item failed for invoice #{invoice.id}: #{e.class}: #{e.message}",
    )
    Honeybadger.notify(e) if defined?(Honeybadger)
  end
end
