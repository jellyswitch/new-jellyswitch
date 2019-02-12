class Subscription < ApplicationRecord
  # Relationships
  belongs_to :user
  belongs_to :plan

  # Scopes
  scope :active, ->() { where(active: true) }

  # Instance methods
  def cancel_stripe!
    stripe_subscription.delete
  end

  def stripe_subscription
    Stripe::Subscription.retrieve(self.stripe_subscription_id)
  end

  def pretty_datetime
    updated_at.strftime("%m/%d/%Y at %l:%M%P")
  end
end
