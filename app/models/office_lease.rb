# == Schema Information
#
# Table name: office_leases
#
#  id                           :bigint(8)        not null, primary key
#  always_allow_building_access :boolean          default(TRUE), not null
#  auto_renew                   :boolean          default(FALSE), not null
#  deposit_amount_in_cents      :integer          default(0), not null
#  end_date                     :date             not null
#  escalation_type              :string
#  escalation_value             :decimal(10, 2)
#  initial_invoice_date         :date
#  renewal_notice_days          :integer          default(60), not null
#  renewal_notice_sent_at       :datetime
#  start_date                   :date             not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  cpi_index_series_id          :string
#  location_id                  :bigint(8)
#  office_id                    :bigint(8)
#  operator_id                  :bigint(8)
#  organization_id              :bigint(8)
#  subscription_id              :bigint(8)
#  user_id                      :bigint(8)
#
# Indexes
#
#  index_office_leases_on_location_id      (location_id)
#  index_office_leases_on_office_id        (office_id)
#  index_office_leases_on_operator_id      (operator_id)
#  index_office_leases_on_organization_id  (organization_id)
#  index_office_leases_on_subscription_id  (subscription_id)
#  index_office_leases_on_user_id          (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (location_id => locations.id) ON DELETE => nullify
#  fk_rails_...  (office_id => offices.id) ON DELETE => nullify
#  fk_rails_...  (operator_id => operators.id) ON DELETE => nullify
#  fk_rails_...  (organization_id => organizations.id) ON DELETE => nullify
#  fk_rails_...  (subscription_id => subscriptions.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id)
#

class OfficeLease < ApplicationRecord
  belongs_to :operator
  belongs_to :organization, optional: true
  belongs_to :user, optional: true
  belongs_to :office
  belongs_to :subscription, dependent: :destroy
  belongs_to :location

  validate :must_have_leasee

  acts_as_scopable :operator, :location

  has_many :lease_renewal_requests, dependent: :destroy
  has_one_attached :lease_agreement

  accepts_nested_attributes_for :subscription

  scope :active, -> { where("now() BETWEEN start_date AND end_date") }
  scope :upcoming, -> { where("start_date > now() AND now() < end_date") }
  scope :inactive, -> { where("end_date <= now()") }

  # Signing an office lease is exactly what the office waitlist exists to
  # deliver, so pull the leasee's office interest tag once they've got one — the
  # fairness queue must never target someone who already leased. For an
  # organization lease this culls every member of that org.
  after_create :cull_office_interest_tags

  RENEWAL_WINDOW_DAYS = 60.freeze

  def has_lease?
    lease_agreement.attached?
  end

  def active?
    Time.current.between?(start_date, end_date)
  end

  def subscription_active?
    subscription.active?
  end

  # Which termination options the operator UI should offer:
  #   :full → both "end of billing cycle" and "now" (live subscription)
  #   :now  → immediate only — a "zombie" lease that's still running but whose
  #           subscription was already cancelled (e.g. the member self-cancelled
  #           or downgraded in the app). Without this the buttons disappeared and
  #           the lease became un-terminable from the UI.
  #   :none → lease isn't currently active
  def termination_options
    return :full if subscription_active?
    return :now if active?

    :none
  end

  def eligible_for_renewal?
    end_date.between?(Date.today, Date.today + RENEWAL_WINDOW_DAYS.days) && active?
  end

  def leasee
    organization || user
  end

  def leasee_name
    organization&.name || user&.name
  end

  def individual_lease?
    user_id.present? && organization_id.blank?
  end

  def group_name
    leasee_name
  end

  def office_name
    office.name
  end

  def set_end_date!
    subscription.set_end_date!(end_date.to_time)
  end

  def pretty_date
    end_date.strftime("%m/%d/%Y")
  end

  def pending_renewal_request
    lease_renewal_requests.pending.order(created_at: :desc).first
  end

  def has_pending_renewal?
    lease_renewal_requests.pending.exists?
  end

  def calculate_renewal_price
    current_price = subscription.plan.amount_in_cents
    case escalation_type
    when "cpi_index"
      rate = CpiCalculator.annual_rate(cpi_index_series_id || "CUSR0000SA0")
      (current_price * (1 + rate / 100.0)).round
    when "percentage"
      (current_price * (1 + (escalation_value || 0) / 100.0)).round
    when "fixed_amount"
      current_price + ((escalation_value || 0) * 100).to_i
    else
      current_price
    end
  end

  def escalation_description
    case escalation_type
    when "cpi_index"
      rate = CpiCalculator.annual_rate(cpi_index_series_id || "CUSR0000SA0")
      "CPI #{cpi_index_series_id || 'CPI-U'} #{rate}%"
    when "percentage"
      "#{escalation_value}% increase"
    when "fixed_amount"
      "#{ActionController::Base.helpers.number_to_currency(escalation_value)} increase"
    else
      "No escalation"
    end
  end

  def current_period_end
    subscription.stripe_subscription&.current_period_end
  end

  private

  def must_have_leasee
    if organization_id.blank? && user_id.blank?
      errors.add(:base, "Must have either an organization or a user")
    end
  end

  def cull_office_interest_tags
    user_ids = []
    user_ids << user_id if user_id.present?
    user_ids.concat(organization.users.ids) if organization_id.present?
    return if user_ids.empty?

    # Scope explicitly to this lease's operator regardless of ambient tenant
    # (leases are created from interactors, the admin API, and renewals).
    ActsAsTenant.with_tenant(operator) do
      InterestTag.for_product("office").where(user_id: user_ids.uniq).destroy_all
    end
  end
end
