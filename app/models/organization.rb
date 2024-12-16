# == Schema Information
#
# Table name: organizations
#
#  id                 :bigint(8)        not null, primary key
#  name               :string           not null
#  out_of_band        :boolean          default(TRUE), not null
#  slug               :string
#  website            :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  billing_contact_id :integer
#  operator_id        :integer          default(1), not null
#  location_id        :integer
#  owner_id           :integer
#  stripe_customer_id :string
#  visible            :boolean          default(TRUE), not null

# Indexes
#
#  index_organizations_on_operator_id  (operator_id)
#

class Organization < ApplicationRecord
  include HasLocation

  searchkick
  # Slugs
  extend FriendlyId
  friendly_id :name, use: :slugged

  # Relationships
  has_many :users, dependent: :nullify
  has_many :office_leases, dependent: :destroy
  has_many :invoices, as: :billable, dependent: :destroy
  belongs_to :owner, class_name: "User", optional: true
  belongs_to :billing_contact, class_name: "User", optional: true
  belongs_to :operator
  acts_as_tenant :operator

  has_many :subscriptions, as: :subscribable, dependent: :destroy

  delegate :email, to: :owner

  scope :eligible_for_lease, -> { where.not(stripe_customer_id: nil).or(where(out_of_band: true)) }
  scope :visible, -> { where(visible: true) }
  scope :archived, -> { where(visible: false) }

  def search_data
    {
      name: name,
      owner: owner.name,
      stripe_customer_id: stripe_customer_id,
    }
  end

  # Form and view helpers
  def self.options_for_select(location)
    Organization.for_location(location).all.map do |org|
      [org.name, org.id]
    end.prepend(["", nil])
  end

  def has_active_lease?(location = nil)
    active_leases(location).length > 0
  end

  def active_leases(location = nil)
    leases = office_leases.active
    leases = leases.where(location: location) if location
    leases
  end

  def stripe_customer_for_location(location)
    return unless stripe_customer_id
    self.location.retrieve_stripe_customer(self)
  end

  def find_or_create_stripe_customer
    stripe_customer || location.create_stripe_customer(self)
  end

  def has_billing_for_location?(location)
    has_stripe_customer_for_location?(location) && card_added?
  end

  def card_added
    stripe_customer.sources["data"].count > 0
  end

  def card_added?
    card_added
  end

  # TODO: since organization is tied to location for now, this passes through
  def card_added_for_location?(location)
    card_added?
  end

  # TODO: since organization is tied to location for now, this passes through
  def stripe_customer_id_for_location(location)
    stripe_customer_id
  end

  # TODO: since organization is tied to location for now, this passes through
  def has_stripe_customer_for_location?(location)
    stripe_customer_id.present?
  end

  def card_last_4_digits(location)
    stripe_customer = stripe_customer_for_location(location)
    if stripe_customer && stripe_customer.sources && stripe_customer.sources.data
      if stripe_customer.sources.data.count < 1
        nil
      else
        cards = stripe_customer.sources.data.select { |source| source.object == "card" }
        if cards.first
          if cards.first.respond_to? :last4
            cards.first.last4
          else
            nil
          end
        else
          nil
        end
      end
    else
      nil
    end
  end

  def payment_method
    if has_billing_for_location?(location)
      "Credit card on file"
    else
      if out_of_band?
        "Via cash or check"
      else
        "None"
      end
    end
  end

  def has_billing_contact?
    billing_contact.present?
  end

  def can_change_billing_contact?
    !has_active_subscriptions? && !has_active_lease?
  end

  def has_active_subscriptions?
    active_subscriptions.count.positive?
  end

  def users_with_active_subscriptions
    users.select do |user|
      if user.bill_to_organization? && user.has_active_subscription?
        user
      end
    end
  end

  def active_subscriptions
    result = []
    users_with_active_subscriptions.each do |user|
      user.subscriptions.active.each do |subscription|
        result << subscription
      end
    end
    result
  end
end
