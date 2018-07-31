class Organization < ApplicationRecord
  # Slugs
  extend FriendlyId
  friendly_id :name, use: :slugged

  # Relationships
  has_many :users
  belongs_to :owner, class_name: "User", optional: true

  # Form and view helpers
  def self.options_for_select
    Organization.all.map do |org|
      [org.name, org.id]
    end.prepend(["", nil])
  end
end
