
class Billing::Invoices::Refunds::Save
  include Interactor
  include FeedItemCreator
  delegate :operator, :invoice, :location, to: :context

  def call
    billable = invoice.billable

    if invoice.cancel
      blob = { type: 'refund', invoice_id: invoice.id }
      create_feed_item(operator, invoice.location || location, billable, blob)
    else
      context.fail!(message: 'Failed to refund invoice')
    end
  end
end
