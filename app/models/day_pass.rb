class DayPass < ApplicationRecord
  # Relationships
  belongs_to :user
  belongs_to :operator
  acts_as_tenant :operator

  # Stripe stuff
  after_create :charge_in_stripe
  def charge_in_stripe
    charge = Stripe::Charge.create({
      amount: Rails.application.config.x.customization.day_pass_cents,
      currency: 'usd',
      description: charge_description,
      customer: user.stripe_customer_id
    })
    self.stripe_charge_id = charge.id
    self.save!
  end

  def charge_description
    "#{Rails.application.config.x.customization.name} Day Pass for #{pretty_day}"
  end

  def stripe_charge
    Stripe::Charge.retrieve(self.stripe_charge_id)
  end

  # Scopes
  scope :today, ->() { where(day: Time.current) }
  scope :fulfilled, ->() { where('stripe_charge_id IS NOT NULL') }

  # Instance methods
  def pretty_day
    day.strftime("%m/%d/%Y")
  end

  def fulfilled?
    stripe_charge_id.present?
  end
end
