# == Schema Information
#
# Table name: users
#
#  id                 :bigint(8)        not null, primary key
#  admin              :boolean          default(FALSE), not null
#  approved           :boolean          default(FALSE), not null
#  bio                :text
#  email              :string           not null
#  linkedin           :string
#  name               :string
#  out_of_band        :boolean          default(FALSE), not null
#  password_digest    :string
#  remember_digest    :string
#  slug               :string
#  superadmin         :boolean          default(FALSE), not null
#  twitter            :string
#  website            :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  operator_id        :integer          default(2), not null
#  organization_id    :integer
#  stripe_customer_id :string
#
# Indexes
#
#  index_users_on_operator_id  (operator_id)
#

class User < ApplicationRecord
  # Relationships
  has_many :day_passes
  has_many :door_punches
  has_many :feed_items
  has_many :invoices
  has_many :member_feedbacks
  belongs_to :organization, optional: true
  belongs_to :operator
  has_many :reservations
  has_many :subscriptions

  # Slugs
  extend FriendlyId
  friendly_id :name, use: :slugged

  # Auth stuff
  attr_accessor :remember_token
  before_save { self.email = email.downcase }
  validates :password, length: { minimum: 6 }, on: :create
  validates :email, uniqueness: true
  has_secure_password

  # Scopes
  scope :approved, ->() { where(approved: true) }
  scope :unapproved, ->() { where(approved: false) }
  scope :members, ->() { where(admin: false) }
  scope :admins, ->() { where(admin: true) }
  scope :for_space, ->(operator) { where('operator_id = ? OR superadmin = true', operator.id) }

  # Relationship Helpers
  def owned_organization
    Organization.where(owner_id: self.id).first
  end

  # Attachments
  has_one_attached :profile_photo

  def square_profile_photo
    profile_photo.variant(resize: "100x100")
  end
  
  def normal_profile_photo
    profile_photo.variant(resize: "250x250")
  end

  # Predicates
  def admin?
    admin
  end

  def superadmin?
    superadmin
  end

  def member?(operator)
    (subscriptions.for_operator(operator).active.count > 0) || (day_passes.fulfilled.today.count > 0)
  end

  def approved?
    approved == true
  end

  def authenticated?(remember_token)
    return false if remember_digest.nil?
    BCrypt::Password.new(remember_digest).is_password?(remember_token)
  end

  def has_profile_photo?
    profile_photo.attached?
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

  # Form and view helpers
  def self.options_for_select
    User.all.map do |user|
      if user.organization.blank?
        [user.name, user.id]
      else
        ["#{user.name} (Organization: #{user.organization.name})", user.id]
      end
    end
  end

  # Stripe Stuff
  def stripe_customer
    Stripe::Customer.retrieve(self.stripe_customer_id)
  end

  def has_billing?
    stripe_customer.sources["data"].count > 0
  end

  def delinquent?
    stripe_customer.delinquent == true
  end
end
