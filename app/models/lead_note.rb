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
end
