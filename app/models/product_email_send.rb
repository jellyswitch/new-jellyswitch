class ProductEmailSend < ApplicationRecord
  acts_as_tenant :operator
  belongs_to :operator
  belongs_to :user
  belongs_to :sendable, polymorphic: true

  validates :email_type, presence: true

  scope :recent, -> { order(sent_at: :desc) }

  def self.already_sent?(sendable, email_type)
    where(sendable: sendable, email_type: email_type).exists?
  end
end
