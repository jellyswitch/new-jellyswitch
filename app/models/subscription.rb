class Subscription < ApplicationRecord
  # Relationships
  belongs_to :user
  belongs_to :plan

  # Scopes
  scope :active, ->() { where(active: true) }

  # Stripe Stuff
  def subscribe_in_stripe!
    subscription = Stripe::Subscription.create({
      customer: user.stripe_customer_id,
      items: [
        { plan: plan.stripe_plan_id }
      ]
    })
    self.stripe_subscription_id = subscription.id
    self.save
  end

  def cancel_stripe!
    stripe_subscription.delete
  end

  def stripe_subscription
    Stripe::Subscription.retrieve(self.stripe_subscription_id)
  end

  # Instance methods

  def pretty_datetime
    updated_at.strftime("%m/%d/%Y at %l:%M%P")
  end
end
