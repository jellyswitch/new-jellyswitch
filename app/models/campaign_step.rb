# == Schema Information
#
# Table name: campaign_steps
#
#  id          :bigint(8)        not null, primary key
#  body        :text             not null
#  delay_days  :integer          default(0), not null
#  position    :integer          default(0), not null
#  sent_count  :integer          default(0)
#  subject     :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  campaign_id :bigint(8)        not null
#
# Indexes
#
#  index_campaign_steps_on_campaign_id               (campaign_id)
#  index_campaign_steps_on_campaign_id_and_position  (campaign_id,position) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (campaign_id => campaigns.id)
#
class CampaignStep < ApplicationRecord
  belongs_to :campaign
  has_many :campaign_sends, dependent: :destroy

  validates :subject, presence: true
  validates :body, presence: true
  validates :position, presence: true, uniqueness: { scope: :campaign_id }
  validates :delay_days, numericality: { greater_than_or_equal_to: 0 }
end
