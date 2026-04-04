class CampaignStep < ApplicationRecord
  belongs_to :campaign
  has_many :campaign_sends, dependent: :destroy

  validates :subject, presence: true
  validates :body, presence: true
  validates :position, presence: true, uniqueness: { scope: :campaign_id }
  validates :delay_days, numericality: { greater_than_or_equal_to: 0 }
end
