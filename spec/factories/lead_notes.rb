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
FactoryBot.define do
  factory :lead_note do
    association :lead
    association :user
    content { "A note about this person." }
  end
end
