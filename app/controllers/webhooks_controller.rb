
class WebhooksController < ApplicationController
  protect_from_forgery except: :stripe

  def stripe
    payload = JSON.parse(request.body.read, symbolize_names: true)
    @event = Stripe::Event.construct_from(payload)

    case @event.type
    when "invoice.finalized"
      if Invoice.exists?(stripe_invoice_id: @event.data.object.id)
        update_status(@event.data.object)
      else
        # TODO: see how we can get a location where this invoice should be created
        result = CreateInvoice.call(stripe_invoice: @event.data.object)
        if result.success? || result.error_message == 'nonexistent-customer'
          ok
        else
          report_error(result.message, __method__)
          error(result.message)
        end
      end
    when "invoice.payment_succeeded", "invoice.payment_failed", "invoice.voided", "invoice.marked_uncollectible"
      if Invoice.exists?(stripe_invoice_id: @event.data.object.id)
        update_status(@event.data.object)
      end
    when "customer.subscription.deleted"
      result = Webhooks::SubscriptionDeleted.call(event: @event)

      if result.success?
        ok
      else
        error(result.message)
      end
    when "customer.subscription.updated"
      result = Webhooks::SubscriptionUpdated.call(event: @event)

      if result.success?
        ok
      else
        error(result.message)
      end
    else
      error("Unrecognized webhook type: #{@event.type}")
    end
  rescue Exception => e
    report_error(e, __method__)
    error(e.message)
  end

  private

  def ok
    render plain: "OK", status: 200
  end

  def error(msg)
    render plain: "ERROR: #{msg}", status: 500
  end

  def update_status(stripe_invoice)
    result = UpdateInvoiceStatus.call(stripe_invoice: stripe_invoice)
    if result.success?
      ok
    else
      report_error(result.message, __method__)
      error(result.message)
    end
  end

  def report_error(msg, meth=nil)
    return unless @event.livemode

    case msg
    when /customer id cus/
      msg, cus_id = msg.split(" cus_")
      Honeybadger.notify(msg, customer_id: "cus_#{cus_id}", method: meth)
    else
      Honeybadger.notify(msg, method: meth)
    end
  end
end
