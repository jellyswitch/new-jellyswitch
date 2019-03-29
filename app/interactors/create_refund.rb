class CreateRefund
  include Interactor
  include FeedItemCreator
  delegate :operator, :invoice, to: :context

  def call
    user = invoice.user

    if invoice.cancel
      blob = { type: 'refund', invoice_id: invoice.id }
      create_feed_item(operator, user, blob)
    else
      context.fail!(message: 'Failed to refund invoice')
    end
  end
end
