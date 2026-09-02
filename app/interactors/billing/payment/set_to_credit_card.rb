class Billing::Payment::SetToCreditCard
  include Interactor

  delegate :user, :location, to: :context

  # Switches a billable back to card billing. Also the only exit from
  # "out of band": it must work for a member with NO card yet (staff flipped
  # out-of-band by mistake), so it no longer fails on a missing card — it
  # clears the flag and records card_added from what Stripe actually holds.
  def call
    payment_profile = user.payment_profile_for_location(location)

    user.subscriptions_billable.active.each do |subscription|
      stripe_sub = subscription.stripe_subscription
      next unless stripe_sub
      stripe_sub.billing = "charge_automatically"
      stripe_sub.save
    end

    has_card = card_on_file?
    payment_profile.update card_added: has_card
    if !user.update(out_of_band: false, bill_to_organization: false, card_added: has_card)
      context.fail!(message: "Unable to update payment method: #{user.errors.full_messages.join(', ')}")
    end
  end

  private

  # SetToOutOfBand zeroes card_added without touching Stripe, so the profile
  # can't tell us whether a card exists — ask Stripe. Any failure reads as
  # "no card" rather than blocking the flag flip.
  def card_on_file?
    return false if location.nil?

    user.card_last_4_digits(location).present?
  rescue StandardError
    false
  end
end
