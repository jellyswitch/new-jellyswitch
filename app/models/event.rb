# == Schema Information
#
# Table name: events
#
#  id                :bigint(8)        not null, primary key
#  approved_at       :datetime
#  description       :text
#  ends_at           :datetime
#  location_string   :string
#  rejected_at       :datetime
#  starts_at         :datetime         not null
#  submitted_via_app :boolean          default(FALSE), not null
#  title             :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  location_id       :integer          not null
#  user_id           :integer          not null
#
# Indexes
#
#  index_events_on_approved_at  (approved_at)
#

class Event < ApplicationRecord
  belongs_to :location
  belongs_to :user

  # Event has no operator_id column; route through the location. Lets
  # Notifiable::Event piggyback on Notifiable::Default's shared
  # `operator` / `apns_configured?` / bundle_id plumbing without
  # overriding everything per-adapter.
  delegate :operator, to: :location, allow_nil: true

  has_many :rsvps

  has_one_attached :image
  
  scope :future, -> () { where("starts_at >= ?", Time.current) }
  scope :past, -> () { where("starts_at < ?", Time.current) }
  scope :today, -> () { where(starts_at: Time.current.beginning_of_day..Time.current.end_of_day) }
  scope :approved, -> () { where.not(approved_at: nil) }
  scope :pending_approval, -> () { where(approved_at: nil, rejected_at: nil) }

  def approved?
    approved_at.present?
  end

  def pending_approval?
    approved_at.nil? && rejected_at.nil?
  end

  def rejected?
    rejected_at.present?
  end

  def thumbnail
    image.variant(resize: "180x180", auto_orient: true)
  end

  def social_image
    image.variant(resize: "500x500", auto_orient: true)
  end
end
