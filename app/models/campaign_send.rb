# == Schema Information
#
# Table name: campaign_sends
#
#  id               :bigint(8)        not null, primary key
#  clicked          :boolean          default(FALSE)
#  clicked_at       :datetime
#  error_message    :string
#  opened           :boolean          default(FALSE)
#  opened_at        :datetime
#  sent_at          :datetime
#  status           :string           default("sent"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  campaign_id      :bigint(8)        not null
#  campaign_step_id :bigint(8)        not null
#  user_id          :bigint(8)        not null
#
# Indexes
#
#  index_campaign_sends_on_campaign_id                   (campaign_id)
#  index_campaign_sends_on_campaign_step_id              (campaign_step_id)
#  index_campaign_sends_on_campaign_step_id_and_user_id  (campaign_step_id,user_id) UNIQUE
#  index_campaign_sends_on_user_id                       (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (campaign_id => campaigns.id)
#  fk_rails_...  (campaign_step_id => campaign_steps.id)
#
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
