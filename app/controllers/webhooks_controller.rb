
class WebhooksController < ApplicationController
  protect_from_forgery except: [:stripe]

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
    when "payment_intent.canceled", "payment_intent.payment_failed"
      # Reservations use manual-capture PaymentIntents. Stripe can
      # auto-cancel them after ~7 days, fraud holds, etc. Mark the
      # reservation payment_failed so the operator sees it and the
      # member gets a heads-up.
      pi_id = @event.data.object.id
      reservation = Reservation.unscoped.find_by(stripe_payment_intent_id: pi_id)
      if reservation && reservation.payment_failed_at.blank? && reservation.captured_at.blank? && !reservation.cancelled?
        reason = @event.data.object.try(:last_payment_error)&.try(:message) ||
                 @event.data.object.try(:cancellation_reason) ||
                 @event.type
        Reservations::MarkPaymentFailed.call(reservation: reservation, reason: reason.to_s) rescue nil
      end
      ok
    when "charge.succeeded"
      # The Payment Element collects ZIP/postal code in the card input. The
      # resulting Charge object carries it through to webhooks at
      # billing_details.address.postal_code. We capture it as a side effect of
      # a successful charge so existing members who pay (subs renewals, day
      # passes, room bookings) backfill home_zip going forward. No frontend
      # change needed — Stripe already passes the postal_code.
      capture_home_zip_from_charge(@event)
      ok

    when "charge.refunded", "refund.created", "charge.refund.updated"
      # A refund issued directly in the Stripe Dashboard never reaches the local
      # Invoice otherwise — it stays `paid`/refundable while Stripe shows it
      # refunded, and the next in-app "Refund" click hits charge_already_refunded
      # (Honeybadger 132040149). Reconcile local state to match Stripe.
      result = Webhooks::ChargeRefunded.call(event: @event)

      if result.success?
        ok
      else
        report_error(result.message, __method__)
        error(result.message)
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

  # Pulls the billing postal_code off a charge.succeeded event and stores it
  # on the paying user's home_zip. Idempotent — only writes when home_zip is
  # blank, so a previously-set value (from signup-geo or manual entry) is
  # preserved. Scoped to the connected account that fired the event so a
  # charge on one operator's Stripe account can never set zip on a user at
  # a different operator.
  def capture_home_zip_from_charge(event)
    charge = event.data.object
    customer_id = charge.try(:customer)
    postal_code = charge.try(:billing_details)&.try(:address)&.try(:postal_code).presence
    connected_account = event.try(:account)

    return unless customer_id.present? && postal_code.present? && connected_account.present?

    operator = Operator.find_by(stripe_user_id: connected_account)
    return unless operator

    user = operator.users.find_by(stripe_customer_id: customer_id)
    return unless user
    return if user.home_zip.present?

    user.update_columns(home_zip: postal_code)
  rescue StandardError => e
    Rails.logger.warn("capture_home_zip_from_charge: #{e.class}: #{e.message}")
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
