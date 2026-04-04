class CampaignSend < ApplicationRecord
  belongs_to :campaign
  belongs_to :campaign_step
  belongs_to :user

  STATUSES = %w[sent failed skipped].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :campaign_step_id, uniqueness: { scope: :user_id }

  scope :sent, -> { where(status: "sent") }
  scope :failed, -> { where(status: "failed") }
  scope :opened, -> { where(opened: true) }
  scope :clicked, -> { where(clicked: true) }

  def self.recently_contacted?(user, days:)
    where(user: user, status: "sent")
      .where("sent_at > ?", days.days.ago)
      .exists?
  end
end
