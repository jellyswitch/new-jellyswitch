# == Schema Information
#
# Table name: users
#
#  id                            :bigint(8)        not null, primary key
#  admin                         :boolean          default(FALSE), not null
#  always_allow_building_access  :boolean          default(FALSE), not null
#  android_token                 :string
#  approved                      :boolean          default(FALSE), not null
#  archived                      :boolean          default(FALSE), not null
#  bill_to_organization          :boolean          default(FALSE), not null
#  bio                           :text
#  card_added                    :boolean          default(FALSE), not null
#  childcare_reservation_balance :integer          default(0), not null
#  confirmation_sent_at          :datetime
#  confirmation_token            :string
#  credit_balance                :integer          default(0), not null
#  email                         :string           not null
#  email_bounced                 :boolean          default(FALSE), not null
#  email_confirmed               :boolean          default(FALSE), not null
#  email_opted_out               :boolean          default(FALSE), not null
#  home_city                     :string
#  home_latitude                 :decimal(10, 7)
#  home_longitude                :decimal(10, 7)
#  home_state                    :string
#  home_zip                      :string
#  inactive_dismissed_at         :datetime
#  ios_token                     :string
#  last_active_at                :datetime
#  linkedin                      :string
#  marketing_consent             :boolean          default(FALSE), not null
#  marketing_suppressed          :boolean          default(FALSE), not null
#  marketing_suppressed_reason   :string
#  name                          :string
#  out_of_band                   :boolean          default(FALSE), not null
#  password_digest               :string
#  phone                         :string
#  preferred_meeting_duration    :integer          default(60)
#  remember_digest               :string
#  reset_digest                  :string
#  reset_sent_at                 :datetime
#  role                          :string           default("unassigned"), not null
#  slug                          :string
#  superadmin                    :boolean          default(FALSE), not null
#  terms_accepted_at             :datetime
#  twitter                       :string
#  website                       :string
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  current_location_id           :integer
#  operator_id                   :integer          default(2), not null
#  organization_id               :integer
#  original_location_id          :integer
#  point_of_contact_id           :bigint(8)
#  preferred_room_id             :bigint(8)
#  stripe_customer_id            :string
#
# Indexes
#
#  index_users_on_home_state_and_home_city       (home_state,home_city)
#  index_users_on_home_zip                       (home_zip)
#  index_users_on_operator_home_state_home_city  (operator_id,home_state,home_city)
#  index_users_on_operator_id                    (operator_id)
#  index_users_on_point_of_contact_id            (point_of_contact_id)
#  index_users_on_preferred_room_id              (preferred_room_id)
#
# Foreign Keys
#
#  fk_rails_...  (point_of_contact_id => users.id)
#

class User < ApplicationRecord
  include ActionText::Attachable
  searchkick
  # Relationships
  has_many :announcements
  has_many :checkins
  has_many :notes, as: :notable, dependent: :destroy
  has_many :child_profiles
  has_many :childcare_reservations, through: :child_profiles
  has_many :day_passes
  has_many :day_pass_bundles
  has_many :door_punches
  has_many :events
  has_many :feed_items
  has_many :feed_item_comments
  has_many :invoices, as: :billable
  has_many :leads
  has_many :lead_notes
  has_many :member_feedbacks
  has_many :feedback_replies
  belongs_to :organization, optional: true
  belongs_to :operator
  belongs_to :original_location, class_name: "Location", optional: true
  belongs_to :current_location, class_name: "Location", optional: true
  has_many :operator_surveys
  has_many :reservations
  has_many :subscriptions, as: :subscribable
  has_many :subscriptions_billable, as: :billable, class_name: "Subscription"
  has_many :refunds
  has_many :rsvps
  has_many :visits, class_name: "Ahoy::Visit"

  has_many :location_managements, dependent: :destroy
  has_many :managed_locations, through: :location_managements, source: :location

  has_many :user_payment_profiles, dependent: :destroy
  has_many :room_demand_misses
  belongs_to :preferred_room, class_name: "Room", optional: true

  # Point of Contact: a staff User who "owns" the relationship with this Person.
  # Reassignable per-Person; survives lifecycle-stage transitions.
  belongs_to :point_of_contact, class_name: "User", optional: true
  has_many :owned_people, class_name: "User", foreign_key: :point_of_contact_id, dependent: :nullify

  alias :location :current_location

  # Reverse geocoding — populate home_city/home_state/home_zip from lat/lng on
  # save. home_zip was added 2026-05-17 to enable sharper local/visitor
  # classification in the CRM; existing users with lat/lng will pick it up
  # automatically on next save, and a backfill rake task pulls zip from Stripe
  # billing addresses for users who already have a stripe_customer_id but no
  # lat/lng (see lib/tasks/users.rake).
  reverse_geocoded_by :home_latitude, :home_longitude do |obj, results|
    if (place = results.first)
      obj.home_city  = place.city
      obj.home_state = place.state_code
      obj.home_zip   = place.postal_code if obj.home_zip.blank?
    end
  end
  after_validation :reverse_geocode, if: -> { home_latitude_changed? || home_longitude_changed? }

  # Slugs
  extend FriendlyId
  friendly_id :name, use: :slugged

  # Auth stuff
  attr_accessor :remember_token, :reset_token, :raw_confirmation_token, :terms_accepted, :admin_created
  before_save { self.email = email.downcase }
  validates :password, length: { minimum: 6 }, on: :create, presence: true
  validates :email, uniqueness: { scope: :operator_id }, presence: true
  validates :name, presence: true
  validates :phone, presence: true, unless: :admin_created, on: :create
  validates :card_added, comparison: { other_than: :out_of_band, if: :card_added? }
  validate :terms_must_be_accepted, on: :create
  has_secure_password

  after_commit :sync_to_mailchimp, if: -> { operator&.mailchimp_api_key.present? && saved_change_to_approved? }
  after_create :assign_default_point_of_contact!
  after_create :log_signup_activity
  after_create :link_default_managed_locations

  has_many :activities, dependent: :destroy

  # Door access ("door_punch") events flood the activity timeline, so the
  # "Recent" feed hides them — EXCEPT the first door access after each
  # join/payment milestone (subscription start, day pass, or payment), which is
  # a meaningful "they've started using the space" signal worth surfacing. The
  # full history lives in the dedicated "Doors" tab.
  DOOR_MILESTONE_ANCHOR_KINDS = %w[subscription_started day_pass payment_succeeded].freeze

  # IDs of the door_punch activities to keep inline in the Recent feed: the
  # earliest punch at/after each anchor event.
  def milestone_door_punch_ids
    anchors = activities.where(kind: DOOR_MILESTONE_ANCHOR_KINDS).order(:occurred_at).pluck(:occurred_at)
    return [] if anchors.empty?

    punches = activities.where(kind: "door_punch").order(:occurred_at).pluck(:id, :occurred_at)
    return [] if punches.empty?

    anchors.filter_map { |t| (pair = punches.bsearch { |p| p[1] >= t }) && pair[0] }.uniq
  end

  # The "Recent" activity feed with door-punch noise removed (keeps only the
  # milestone punches). Shared by the web timeline and the mobile API.
  def recent_timeline_activities(limit: 50)
    keep = milestone_door_punch_ids
    scope = activities.recent
    scope = if keep.empty?
              scope.where.not(kind: "door_punch")
            else
              scope.where("activities.kind <> 'door_punch' OR activities.id IN (?)", keep)
            end
    scope.limit(limit)
  end

  # Lifecycle stage — derived at query time, never stored (ADR-0002).
  # Grace days reads from current_location.past_member_grace_days, falling
  # back to DEFAULT_PAST_MEMBER_GRACE_DAYS when the user has no current_location.
  DEFAULT_PAST_MEMBER_GRACE_DAYS = 180
  LIFECYCLE_STAGES = %i[member past_member day_passer quiet tour_taker signup_only].freeze
  LIFECYCLE_PRIOR_ACTIVITY_KINDS = %w[checkin door_punch reservation day_pass subscription_started].freeze
  LIFECYCLE_VISIT_KINDS = %w[checkin door_punch reservation].freeze
  RECENT_DAY_PASS_DAYS = 30
  QUIET_THRESHOLD_DAYS = 30

  def log_signup_activity
    Activity.log(user: self, kind: :signup, subject: self, operator: operator)
  end

  # Auto-assigns a default point-of-contact when this Person doesn't have one.
  # Priority: current_location's general-manager → operator's primary admin.
  # No-op if PoC already set, if the user is staff themselves, or if no
  # candidate exists. Phase 4.3 will add a manual reassignment UI.
  STAFF_ROLES = %w[community-manager general-manager admin superadmin].freeze

  def assign_default_point_of_contact!
    return if point_of_contact_id.present?
    return if STAFF_ROLES.include?(role)

    candidate = default_point_of_contact_candidate
    update_column(:point_of_contact_id, candidate.id) if candidate
  end

  WELCOME_DRIP_ENROLLED_KEY = "welcome_drip_enrolled".freeze

  # Mark this Person as enrolled in the Welcome Drip. Idempotent: no-op if
  # already enrolled, if the user is currently an active member, or if
  # the one-active-series invariant says they're in another drip already.
  #
  # The welcome drip is *foundational onboarding*, not a marketing follow-up.
  # System / transactional sends (account confirmation, day-pass receipt,
  # password resets) must not gate it — otherwise every brand-new day-passer
  # gets silently excluded because their signup confirmation email is within
  # the 30-day cool-down. `cool_down_days: 0` skips SpamGuard's
  # recently-emailed check while still honoring the in-active-drip and
  # in-welcome-drip guards (ADR-0003's series invariant).
  def enroll_in_welcome_drip!
    return false if has_active_subscription?
    return false if welcome_drip_enrolled?
    return false unless SpamGuard.eligible?(self, sender: operator, cool_down_days: 0)

    ProductEmailSend.create!(
      operator: operator,
      user: self,
      sendable: self,
      email_type: WELCOME_DRIP_ENROLLED_KEY,
      status: "scheduled",
      sent_at: Time.current,
    )
    true
  rescue ActiveRecord::RecordNotUnique
    false
  end

  def welcome_drip_enrolled?
    ProductEmailSend.where(sendable_type: "User", sendable_id: id,
                           email_type: WELCOME_DRIP_ENROLLED_KEY).exists?
  end

  def to_activity_payload
    {
      "name" => name,
      "email" => email,
    }
  end

  def lifecycle_stage
    return :member if active_subscription? || subscription_ended_within_grace?
    return :day_passer if recent_day_pass?
    return :past_member if subscription_ended_past_grace?
    return :quiet if previously_active? && !recent_visit?
    return :tour_taker if has_logged_tour?
    :signup_only
  end

  def self.in_stage(stage)
    stage = stage.to_sym
    raise ArgumentError, "unknown lifecycle stage: #{stage}" unless LIFECYCLE_STAGES.include?(stage)

    day_pass_cutoff = RECENT_DAY_PASS_DAYS.days.ago.to_date
    visit_cutoff = QUIET_THRESHOLD_DAYS.days.ago

    active_sub_ids = Subscription.where(subscribable_type: "User", active: true).pluck(:subscribable_id)

    grace_join = <<~SQL
      INNER JOIN users ON users.id = activities.user_id
      LEFT JOIN locations ON locations.id = users.current_location_id
    SQL
    grace_cutoff_sql = "activities.occurred_at >= NOW() - (COALESCE(locations.past_member_grace_days, ?) * INTERVAL '1 day')"
    in_grace_ids = Activity.where(kind: "subscription_ended")
                           .joins(grace_join)
                           .where(grace_cutoff_sql, DEFAULT_PAST_MEMBER_GRACE_DAYS)
                           .pluck("activities.user_id")
    past_grace_ids = Activity.where(kind: "subscription_ended")
                             .joins(grace_join)
                             .where("NOT (#{grace_cutoff_sql})", DEFAULT_PAST_MEMBER_GRACE_DAYS)
                             .pluck("activities.user_id")
    recent_day_pass_ids = DayPass.where("day >= ?", day_pass_cutoff).pluck(:user_id)
    prior_active_ids = Activity.where(kind: LIFECYCLE_PRIOR_ACTIVITY_KINDS).pluck(:user_id)
    recent_visit_ids = Activity.where(kind: LIFECYCLE_VISIT_KINDS)
                               .where("occurred_at >= ?", visit_cutoff).pluck(:user_id)
    tour_ids = Activity.where(kind: "tour").pluck(:user_id).uniq

    member_ids = (active_sub_ids + in_grace_ids).uniq

    case stage
    when :member
      where(id: member_ids)
    when :day_passer
      where(id: recent_day_pass_ids - member_ids)
    when :past_member
      where(id: (past_grace_ids - member_ids - recent_day_pass_ids).uniq)
    when :quiet
      quiet_ids = prior_active_ids - member_ids - recent_day_pass_ids - past_grace_ids - recent_visit_ids
      where(id: quiet_ids.uniq)
    when :tour_taker
      # Now requires an actual tour Activity record — was previously the catch-all
      # fallback for anyone not in another stage, which over-labeled hundreds of
      # users who never had a tour.
      quiet_ids = prior_active_ids - member_ids - recent_day_pass_ids - past_grace_ids - recent_visit_ids
      excluded = (member_ids + recent_day_pass_ids + past_grace_ids + quiet_ids).uniq
      where(id: tour_ids - excluded)
    when :signup_only
      # New stage that absorbs the old default fallback: people who signed up
      # but never engaged AND never had a tour logged.
      quiet_ids = prior_active_ids - member_ids - recent_day_pass_ids - past_grace_ids - recent_visit_ids
      excluded = (member_ids + recent_day_pass_ids + past_grace_ids + quiet_ids + tour_ids).uniq
      where.not(id: excluded)
    end
  end

  private

  def active_subscription?
    subscriptions.where(active: true).exists?
  end

  def subscription_ended_within_grace?
    activities.where(kind: "subscription_ended")
              .where("occurred_at >= ?", past_member_grace_days_threshold.days.ago)
              .exists?
  end

  def subscription_ended_past_grace?
    activities.where(kind: "subscription_ended")
              .where("occurred_at < ?", past_member_grace_days_threshold.days.ago)
              .exists?
  end

  def past_member_grace_days_threshold
    current_location&.past_member_grace_days || DEFAULT_PAST_MEMBER_GRACE_DAYS
  end

  def recent_day_pass?
    day_passes.where("day >= ?", RECENT_DAY_PASS_DAYS.days.ago.to_date).exists?
  end

  def previously_active?
    activities.where(kind: LIFECYCLE_PRIOR_ACTIVITY_KINDS).exists?
  end

  def recent_visit?
    activities.where(kind: LIFECYCLE_VISIT_KINDS)
              .where("occurred_at >= ?", QUIET_THRESHOLD_DAYS.days.ago)
              .exists?
  end

  def has_logged_tour?
    activities.where(kind: "tour").exists?
  end

  def default_point_of_contact_candidate
    return nil if operator.nil?

    if current_location
      gm = operator.users.where(role: "general-manager", current_location_id: current_location.id)
                          .order(:created_at).first
      return gm if gm
    end
    operator.users.where(role: "admin").order(:created_at).first
  end

  public

  # Scopes
  scope :approved, -> { where(approved: true) }
  scope :unapproved, -> { where(approved: false) }
  scope :archived, -> { where(archived: true) }
  scope :visible, -> { where(archived: false) }
  scope :members, -> { where(role: User::UNASSIGNED) }
  scope :admins, -> { where(role: User::ADMIN) }
  scope :community_managers, -> { where(role: User::COMMUNITY_MANAGER) }
  scope :general_managers, -> { where(role: User::GENERAL_MANAGER) }
  scope :taggable, -> { admins.or(general_managers.or(community_managers)) }
  # Who can be @mentioned in a note: all staff PLUS approved, non-archived
  # members. (Distinct from :taggable, which stays staff-only because the
  # profile "managed by" dropdown uses it — we don't want every member there.)
  scope :mentionable, -> {
    base = where(archived: [false, nil])
    base.where(role: [User::ADMIN, User::GENERAL_MANAGER, User::COMMUNITY_MANAGER])
        .or(base.where(role: User::UNASSIGNED, approved: true))
  }
  scope :non_superadmins, -> { where.not(role: User::SUPERADMIN) }
  scope :for_space, ->(operator) { where("operator_id = ?", operator.id) }
  scope :superadmins, -> { where(role: User::SUPERADMIN) }
  scope :not_in_organization, ->(organization) { where("organization_id != ? OR organization_id IS NULL", organization.id) }
  scope :originally_at_location, ->(location) { location.present? ? where(original_location_id: location.id) : all }
  scope :currently_at_location, ->(location) { location.present? ? where(current_location_id: location.id) : all }

  scope :relevant_admins_of_location, ->(location) {
    if location.present?
      # An admin is relevant to a location they manage (location_managements).
      # A superadmin is relevant to a location they manage OR the one they're
      # currently switched to. Previously superadmins matched ONLY by
      # current_location_id, so a superadmin who manages location A but is
      # currently switched to a sibling location B silently stopped receiving
      # A's notifications (e.g. a multi-location operator's owner). Match
      # superadmins by managed location too.
      left_joins(:location_managements)
        .where("(users.role = ? AND (users.current_location_id = ? OR location_managements.location_id = ?)) OR (users.role = ? AND location_managements.location_id = ?)",
              User::SUPERADMIN, location.id, location.id, User::ADMIN, location.id)
        .distinct
    else
      none
    end
  }

  # Permissions
  delegate :member_at_operator?,
           :member?,
           :books_outside_posted_hours?,
           :has_active_subscription_at_location?,
           :admin?,
           :superadmin?,
           :community_manager?,
           :general_manager?,
           :admin_or_manager?,
           :pending?,
           :has_building_access?,
           :has_active_subscription?,
           :has_building_access_membership?,
           :has_active_day_pass?,
           :has_building_access_day_pass?,
           :has_active_day_pass_bundle?,
           :has_active_lease?,
           :has_building_access_lease?,
           :organization_owner?,
           :visible?,
           :member_of_organization?,
           :authenticated?,
           :has_profile_photo?,
           :checked_in?,
           :has_active_reservation?,
           :allowed_in?,
           :should_charge_for_reservation?,
           :should_charge_for_room?,
           :can_see_all_rooms?,
           :member_at_location?,
           :admin_of_location?,
           :currently_at_location?,
           :day_pass_reservation_charge_info,
           :subscription_reservation_charge_info,
           :active_subscription_for_location,
           to: :user_permissions

  # Roles
  UNASSIGNED = "unassigned".freeze
  COMMUNITY_MANAGER = "community-manager".freeze
  GENERAL_MANAGER = "general-manager".freeze
  ADMIN = "admin".freeze
  SUPERADMIN = "superadmin".freeze

  def role_options_for_select
    eligible_roles = User.roles

    # Only superadmins can assign superadmin role
    if role != SUPERADMIN
      eligible_roles -= [SUPERADMIN]
    end

    if role == GENERAL_MANAGER
      eligible_roles -= [ADMIN]
    end

    eligible_roles.map { |r| [r.titleize, r] }
  end

  def managed_location_options_for_select
    eligible_locations = operator.locations

    if role != SUPERADMIN
      eligible_locations = managed_locations
    end

    eligible_locations.map { |location| [location.name, location.id] }
  end

  def self.roles
    [
      UNASSIGNED,
      COMMUNITY_MANAGER,
      GENERAL_MANAGER,
      ADMIN,
      SUPERADMIN,
    ].freeze
  end

  def search_data
    {
      name: name,
      email: email,
      stripe_customer_id: stripe_customer_id_for_location(original_location),
      bio: bio,
      slug: slug,
      twitter: twitter,
      organization: organization.present? ? organization.name : nil,
      operator_id: operator_id,
    }
  end

  # Relationship Helpers
  def owned_organization
    Organization.where(owner_id: self.id).first
  end

  # Attachments
  has_one_attached :profile_photo

  def small_square_profile_photo
    profile_photo.variant(resize: "65x65>", gravity: "Center", crop: "50x50+0+0")
  end

  def square_profile_photo
    profile_photo.variant(resize: "100x100>")
  end

  def normal_profile_photo
    profile_photo.variant(resize: "250x250")
  end

  def owned_organization
    operator.organizations.find_by(owner_id: self.id)
  end

  def organization_name
    if organization.present?
      organization.name
    else
      "None"
    end
  end

  def to_trix_content_attachment_partial_path
    to_partial_path
  end

  def upcoming_or_ongoing_reservation(location_id = nil)
    reservations.for_location_id(location_id).ongoing.order(:datetime_in).first ||
    reservations.for_location_id(location_id).future.order(:datetime_in).first
  end

  # Auth Stuff
  def self.digest(string)
    cost = ActiveModel::SecurePassword.min_cost ? BCrypt::Engine::MIN_COST : BCrypt::Engine.cost
    BCrypt::Password.create(string, cost: cost)
  end

  def self.new_token
    SecureRandom.urlsafe_base64
  end

  def remember
    self.remember_token = User.new_token
    update_attribute(:remember_digest, User.digest(remember_token))
  end

  def forget
    update_attribute(:remember_digest, nil)
  end

  def self.find_by_operator(params)
    email = params[:email]
    operator_id = params[:operator_id]

    user = User.find_by(email: email)
    if user.present? && user.superadmin?
      return user
    else
      return User.find_by(email: email, operator_id: operator_id)
    end
  end

  def create_reset_digest
    self.reset_token = User.new_token
    update_attribute(:reset_digest, User.digest(reset_token))
    update_attribute(:reset_sent_at, Time.zone.now)
  end

  def send_password_reset_email
    UserMailer.password_reset(self, operator, reset_token).deliver_now
  end

  def password_reset_expired?
    reset_sent_at < 2.hours.ago
  end

  # Email confirmation
  def generate_confirmation_token
    self.raw_confirmation_token = User.new_token
    update_attribute(:confirmation_token, User.digest(raw_confirmation_token))
    update_attribute(:confirmation_sent_at, Time.zone.now)
  end

  def send_confirmation_email
    UserMailer.email_confirmation(self, operator, raw_confirmation_token).deliver_now
  end

  def confirm_email!
    update_columns(email_confirmed: true, confirmation_token: nil, confirmation_sent_at: nil)
  end

  def confirmation_expired?
    confirmation_sent_at.nil? || confirmation_sent_at < 24.hours.ago
  end

  def valid_confirmation_token?(token)
    return false if confirmation_token.nil?
    BCrypt::Password.new(confirmation_token).is_password?(token)
  end

  # Form and view helpers
  def self.options_for_select(operator)
    User.for_space(operator).all.map do |user|
      option_helper(user)
    end
  end

  def self.lease_options_for_select(operator, location)
    User.for_space(operator).originally_at_location(location).non_superadmins.approved.visible.order(:name).all.map do |user|
      option_helper(user)
    end
  end

  # Filtered list for reservation member selection:
  # Only includes paying members, day pass holders (today or future),
  # users with a paid reservation (current or future), and admins/managers.
  # Returns the requesting admin first, then the rest alphabetically.
  def self.reservation_options_for_select(operator, location, requesting_user)
    today = Time.current.to_date

    # Load all users at this location (proven working query)
    all_users = User.for_space(operator)
                    .originally_at_location(location)
                    .non_superadmins
                    .visible
                    .includes(:organization, :subscriptions, :day_passes, :reservations)
                    .order(:name)

    # Collect IDs of eligible day pass holders and reservation holders
    day_pass_user_ids = DayPass.where("day >= ?", today).pluck(:user_id).to_set
    reservation_user_ids = Reservation.where("datetime_in >= ?", Time.current)
                                      .where(cancelled: false)
                                      .pluck(:user_id).to_set

    # Plan IDs for this location
    location_plan_ids = Plan.where(location_id: location.id).pluck(:id).to_set

    admin_id = requesting_user.id

    eligible = all_users.select do |user|
      user.id == admin_id ||
      [User::ADMIN, User::GENERAL_MANAGER, User::COMMUNITY_MANAGER].include?(user.role) ||
      user.subscriptions.any? { |s| s.active? && location_plan_ids.include?(s.plan_id) } ||
      day_pass_user_ids.include?(user.id) ||
      reservation_user_ids.include?(user.id) ||
      (user.organization.present? && user.organization.has_active_lease?(location))
    end

    # Sort: requesting admin first, then alphabetically
    eligible.sort_by! { |u| [u.id == admin_id ? 0 : 1, u.name.to_s.downcase] }

    eligible.map { |user| option_helper(user) }
  rescue => e
    Rails.logger.error("reservation_options_for_select error: #{e.class}: #{e.message}")
    Rails.logger.error(e.backtrace&.first(10)&.join("\n"))
    # Fall back to the full user list so the page still loads
    lease_options_for_select(operator, location)
  end

  def self.option_helper(user)
    if user.organization.blank?
      [user.name, user.id]
    else
      ["#{user.name} (Organization: #{user.organization.name})", user.id]
    end
  end

  # Stripe Stuff
  def stripe_customer_for_location(location)
    @stripe_customer ||= location.retrieve_stripe_customer(self)
  end

  def has_stripe_customer_for_location?(location)
    stripe_customer_id_for_location(location).present?
  end

  # This is used in views, important
  def has_billing_for_location?(location)
    has_stripe_customer_for_location?(location) && (out_of_band? || card_added_for_location?(location))
  end

  def delinquent?
    stripe_customer.delinquent == true
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
    if bill_to_organization
      "Bill to Group"
    else
      if out_of_band?
        "Out of band"
      else
        if card_added?
          "Credit card on file"
        else
          "None"
        end
      end
    end
  end

  def user_permissions
    @user_permissions ||= UserPermissions.new(self)
  end

  # On creation, link a manager (admin/GM/CM) with no explicit location scoping
  # to all of their operator's locations. This keeps direct readers of
  # managed_location_ids (e.g. the admin API's enforce_location_scope!) correct
  # and consistent with the manages_location? fallback. Onboarding previously
  # created no location_managements row at all, which locked new operator admins
  # out of room/door/etc. admin. Subsequent scoping changes go through the admin
  # user-edit form, which sets managed_location_ids explicitly. Pure superadmins
  # (no admin role/flag) are skipped — they bypass location scoping anyway.
  def link_default_managed_locations
    return unless operator
    return unless admin? || general_manager? || community_manager?
    return if managed_location_ids.any?

    ids = operator.location_ids
    return if ids.blank?

    self.managed_location_ids = ids
  end

  def manages_location?(location)
    return false if location.nil?

    # Explicit scoping wins: a manager assigned specific locations manages only
    # those. With no explicit assignment, a manager manages every location of
    # their own operator. This is the safe default for a freshly-onboarded
    # operator whose admin has no location_managements row yet — onboarding
    # never creates one (only the one-time set_location_managers backfill and
    # the manual admin user-edit form do), which previously left new operator
    # admins unable to manage rooms/doors/etc. Never crosses operator
    # boundaries; superadmins bypass this via admin_of_location?.
    if managed_location_ids.any?
      managed_location_ids.include?(location.id)
    else
      location.operator_id == operator_id
    end
  end

  def admin_of_location?(location)
    (admin? && manages_location?(location)) || superadmin?
  end

  def general_manager_of_location?(location)
    (general_manager? && manages_location?(location))
  end

  def community_manager_of_location?(location)
    (community_manager? && manages_location?(location))
  end

  # payment profile methods
  def payment_profile_for_location(location)
    payment_profile = user_payment_profiles.find_or_create_by(location: location)

    if payment_profile.previously_new_record?
      stripe_customer = location.create_stripe_customer(self)
      payment_profile.stripe_customer_id = stripe_customer.id
      payment_profile.save
    end

    payment_profile
  end

  def stripe_customer_id_for_location(location)
    payment_profile_for_location(location)&.stripe_customer_id
  end

  def card_added_for_location?(location)
    payment_profile_for_location(location)&.card_added
  end

  def update_stripe_customer_id_for_location(location, stripe_customer_id)
    payment_profile = payment_profile_for_location(location)
    payment_profile.update stripe_customer_id: stripe_customer_id
  end

  def update_card_added_for_location(location, card_added)
    payment_profile = payment_profile_for_location(location)
    payment_profile.update card_added: card_added
  end

  def self.find_by_stripe_customer_id(stripe_customer_id)
    user_payment_profile = UserPaymentProfile.find_by(stripe_customer_id: stripe_customer_id)
    user_payment_profile&.user
  end

  # TODO: probably legacy functionality
  # def bill_to_organization_for_location(location)
  #   payment_profile_for_location(location)&.bill_to_organization
  # end

  class UserPermissions < SimpleDelegator
    include Permissions
  end

  private_constant :UserPermissions

  private

  def terms_must_be_accepted
    return if admin_created
    return unless operator&.terms_of_service&.attached?
    return if terms_accepted_at.present?
    return if terms_accepted == "1" || terms_accepted == true

    errors.add(:terms_accepted, "must be accepted to create an account")
  end

  def sync_to_mailchimp
    MailchimpSyncJob.perform_later(id)
  end
end
