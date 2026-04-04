
class WebhooksController < ApplicationController
  protect_from_forgery except: [:stripe, :sendgrid_events]

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
    when "invoice.payment_succeeded", "invoice.voided", "invoice.marked_uncollectible"
      if Invoice.exists?(stripe_invoice_id: @event.data.object.id)
        update_status(@event.data.object)
      else
        ok
      end
    when "invoice.payment_failed"
      if Invoice.exists?(stripe_invoice_id: @event.data.object.id)
        update_status(@event.data.object)

        # Send payment failed recovery email and notify admins
        begin
          invoice = Invoice.find_by(stripe_invoice_id: @event.data.object.id)
          if invoice
            SendPaymentFailedEmailJob.perform_later(invoice.stripe_invoice_id, invoice.operator_id)

            # Create feed item to alert admins
            user = invoice.billable.is_a?(User) ? invoice.billable : invoice.billable.try(:owner)
            if user
              amount = ActionController::Base.helpers.number_to_currency(invoice.amount_due / 100.0)
              FeedItemCreator.create_feed_item(
                invoice.operator,
                invoice.location,
                user,
                { text: "Payment failed for #{amount} invoice.", type: "payment_failed" }
              )
            end
          end
        rescue => e
          Rails.logger.error("Payment failed notification error: #{e.class}: #{e.message}")
          Honeybadger.notify(e)
        end
      else
        ok
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
      # Acknowledge unhandled event types so Stripe doesn't retry them
      ok
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

  # SendGrid Event Webhook — handles bounces and engagement tracking
  # Configure in SendGrid: Settings > Mail Settings > Event Webhook
  def sendgrid_events
    events = JSON.parse(request.body.read)
    events.each do |event|
      email = event["email"]&.downcase
      next unless email.present?

      case event["event"]
      when "bounce", "dropped"
        User.where("lower(email) = ?", email).update_all(email_bounced: true)
      when "open"
        # Track opens for campaign sends
        CampaignSend.where(user: User.where("lower(email) = ?", email))
          .where(opened: false)
          .update_all(opened: true, opened_at: Time.current)
      when "click"
        CampaignSend.where(user: User.where("lower(email) = ?", email))
          .where(clicked: false)
          .update_all(clicked: true, clicked_at: Time.current)
      end
    rescue => e
      Rails.logger.warn("SendGrid event processing error: #{e.message}")
    end

    head :ok
  end
end
