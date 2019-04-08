# == Schema Information
#
# Table name: organizations
#
#  id                 :bigint(8)        not null, primary key
#  name               :string           not null
#  out_of_band        :boolean          default(FALSE), not null
#  slug               :string
#  website            :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  operator_id        :integer          default(1), not null
#  owner_id           :integer
#  stripe_customer_id :string
#
# Indexes
#
#  index_organizations_on_operator_id  (operator_id)
#

class Organization < ApplicationRecord
  # Slugs
  extend FriendlyId
  friendly_id :name, use: :slugged

  # Relationships
  has_many :users
  belongs_to :owner, class_name: "User", optional: true
  belongs_to :operator
  acts_as_tenant :operator

  has_one :subscription, as: :subscribable

  # Form and view helpers
  def self.options_for_select
    Organization.all.map do |org|
      [org.name, org.id]
    end.prepend(["", nil])
  end

  def stripe_customer
    return unless stripe_customer_id
    operator.retrieve_stripe_customer(self)
  end

  def find_or_create_stripe_customer
    stripe_customer || operator.create_stripe_customer(self)
  end

  def has_billing?
    has_stripe_customer? && stripe_customer.sources["data"].count > 0
  end
end
