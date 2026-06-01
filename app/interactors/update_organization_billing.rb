
class UpdateOrganizationBilling
  include Interactor

  delegate :organization, :stripe_token, :out_of_band, to: :context

  def call
    was_out_of_band = organization.out_of_band?

    if out_of_band
      organization.update(out_of_band: true)
      # Only sync to Stripe if we actually transitioned. No-op flips don't
      # need to spam the Stripe API.
      sync_stripe_subscriptions!(billing: "send_invoice") if !was_out_of_band
    else
      stripe_customer = organization.find_or_create_stripe_customer
      stripe_customer.source = stripe_token
      organization.stripe_customer_id = stripe_customer.id
      organization.out_of_band = false

      unless stripe_customer.save && organization.save
        context.fail!(message: "Unable to update billing info.")
      end

      # CRITICAL — when switching from OOB to card billing, ALSO update any
      # existing Stripe subscriptions on this org to charge_automatically.
      # Without this, the Stripe sub stays on send_invoice forever and
      # Stripe quietly creates `open` invoices without ever charging the
      # card we just added (the Aimee Dalton / Wild and Well Studio bug,
      # 2026-05-30). Stripe uses the customer's default source/PM, so we
      # don't need to set default_payment_method on each subscription.
      sync_stripe_subscriptions!(billing: "charge_automatically") if was_out_of_band
    end
  end

  private

  # Walks active subscriptions on this org and updates each Stripe
  # subscription's `billing` field (Stripe API field name on api_version
  # 2018-11-08 — equivalent to `collection_method` on newer versions).
  # Best-effort: individual Stripe failures don't abort the local flag flip,
  # but we surface them via Honeybadger so an out-of-sync subscription is
  # visible rather than silent.
  def sync_stripe_subscriptions!(billing:)
    organization.subscriptions.active.each do |subscription|
      stripe_sub = subscription.stripe_subscription
      next unless stripe_sub

      stripe_sub.billing = billing
      stripe_sub.days_until_due = (billing == "send_invoice") ? 30 : nil
      stripe_sub.save
    rescue Stripe::StripeError => e
      Honeybadger.notify(e, context: {
        organization_id: organization.id,
        subscription_id: subscription.id,
        stripe_subscription_id: subscription.stripe_subscription_id,
        target_billing: billing,
      })
    end
  end
end
