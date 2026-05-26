# == Schema Information
#
# Table name: lease_renewal_requests
#
#  id                      :bigint(8)        not null, primary key
#  admin_notes             :text
#  admin_responded_at      :datetime
#  current_price_in_cents  :integer          not null
#  escalation_applied      :string
#  expires_at              :datetime
#  leasee_notes            :text
#  leasee_responded_at     :datetime
#  proposed_end_date       :date             not null
#  proposed_price_in_cents :integer          not null
#  proposed_start_date     :date             not null
#  status                  :string           default("pending_leasee"), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  location_id             :bigint(8)
#  office_lease_id         :bigint(8)        not null
#  operator_id             :bigint(8)        not null
#
# Indexes
#
#  index_lease_renewal_requests_on_location_id                 (location_id)
#  index_lease_renewal_requests_on_office_lease_id             (office_lease_id)
#  index_lease_renewal_requests_on_office_lease_id_and_status  (office_lease_id,status)
#  index_lease_renewal_requests_on_operator_id                 (operator_id)
#
# Foreign Keys
#
#  fk_rails_...  (location_id => locations.id)
#  fk_rails_...  (office_lease_id => office_leases.id)
#  fk_rails_...  (operator_id => operators.id)
#
class LeaseRenewalRequest < ApplicationRecord
  belongs_to :office_lease
  belongs_to :operator
  belongs_to :location, optional: true

  acts_as_tenant :operator

  STATUSES = %w[pending_leasee pending_admin approved declined expired].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :proposed_price_in_cents, :current_price_in_cents, numericality: { greater_than: 0 }
  validates :proposed_start_date, :proposed_end_date, presence: true

  scope :pending, -> { where(status: %w[pending_leasee pending_admin]) }
  scope :pending_leasee, -> { where(status: "pending_leasee") }
  scope :pending_admin, -> { where(status: "pending_admin") }
  scope :resolved, -> { where(status: %w[approved declined expired]) }

  def pending?
    status.start_with?("pending")
  end

  def pending_leasee?
    status == "pending_leasee"
  end

  def pending_admin?
    status == "pending_admin"
  end

  def approved?
    status == "approved"
  end

  def declined?
    status == "declined"
  end

  def expired?
    status == "expired"
  end

  def leasee
    office_lease.leasee
  end

  def leasee_name
    office_lease.leasee_name
  end

  def proposed_price_formatted
    ActionController::Base.helpers.number_to_currency(proposed_price_in_cents / 100.0)
  end

  def current_price_formatted
    ActionController::Base.helpers.number_to_currency(current_price_in_cents / 100.0)
  end

  def price_increase_formatted
    increase = proposed_price_in_cents - current_price_in_cents
    return nil if increase <= 0
    ActionController::Base.helpers.number_to_currency(increase / 100.0)
  end

  def accept!(notes: nil)
    update!(
      status: "approved",
      leasee_notes: notes,
      leasee_responded_at: Time.current
    )
  end

  def request_modification!(notes:)
    update!(
      status: "pending_admin",
      leasee_notes: notes,
      leasee_responded_at: Time.current
    )
  end

  def admin_approve!(notes: nil, price_override: nil)
    attrs = {
      status: "approved",
      admin_notes: notes,
      admin_responded_at: Time.current
    }
    attrs[:proposed_price_in_cents] = price_override if price_override.present?
    update!(attrs)
  end

  def admin_decline!(notes: nil)
    update!(
      status: "declined",
      admin_notes: notes,
      admin_responded_at: Time.current
    )
  end

  def expire!
    update!(status: "expired") if pending?
  end
end
