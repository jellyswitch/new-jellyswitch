# == Schema Information
#
# Table name: leads
#
#  id            :bigint(8)        not null, primary key
#  source        :string
#  status        :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  ahoy_visit_id :integer
#  operator_id   :integer          not null
#  user_id       :integer          not null
#

class Lead < ApplicationRecord
  belongs_to :operator
  belongs_to :user
  belongs_to :ahoy_visit, class_name: "Ahoy::Visit", optional: true

  has_many :lead_notes

  after_create :set_status
  after_create :set_source
  after_create :assign_default_point_of_contact_to_user
  after_create :enroll_user_in_welcome_drip_from_event

  def assign_default_point_of_contact_to_user
    return if user.point_of_contact_id.present?
    user.assign_default_point_of_contact!
  end

  # Auto-enroll Persons who arrive via an event RSVP. Other Lead sources
  # (web tour-request, referral) are deferred — they may be hand-curated
  # by ops and don't always indicate the same level of interest.
  def enroll_user_in_welcome_drip_from_event
    return unless source.to_s == Lead::SOURCES[:event]
    user&.enroll_in_welcome_drip!
  end

  SOURCES = {
    web: "web",
    event: "event",
    referral: "referral"
  }

  STATUSES = {
    open: "open",
    closed_lost: "closed-lost",
    closed_won: "closed-won"
  }

  def set_status
    if status.blank?
      update(status: STATUSES[:open])
    end
  end

  def set_source
    if source.blank?
      if ahoy_visit.present?
        update(source: SOURCES[:web])
      end
    end
  end

  def gravatar
    hash = Digest::MD5.hexdigest(user.email)
    "https://www.gravatar.com/avatar/#{hash}"
  end
end
