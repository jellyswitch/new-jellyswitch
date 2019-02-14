# == Schema Information
#
# Table name: organizations
#
#  id          :bigint(8)        not null, primary key
#  name        :string           not null
#  owner_id    :integer
#  website     :string
#  slug        :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  operator_id :integer          default(1), not null
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

  # Form and view helpers
  def self.options_for_select
    Organization.all.map do |org|
      [org.name, org.id]
    end.prepend(["", nil])
  end
end
