# == Schema Information
#
# Table name: lead_notes
#
#  id         :bigint(8)        not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  lead_id    :integer          not null
#  user_id    :integer          not null
#
class LeadNote < ApplicationRecord
  belongs_to :lead
  belongs_to :user

  has_rich_text :content

  after_create :log_activity

  def log_activity
    Activity.log(
      user: lead.user,
      kind: :note,
      subject: self,
      operator: lead.operator,
    )
  end

  def to_activity_payload
    {
      "author_user_id" => user_id,
      "author_name" => user&.name,
      "content_preview" => content&.to_plain_text&.truncate(140),
    }
  end
end
