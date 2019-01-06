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
