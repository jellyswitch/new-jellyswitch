# == Schema Information
#
# Table name: leads
#
#  id            :bigint(8)        not null, primary key
#  status        :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  ahoy_visit_id :integer
#  operator_id   :integer          not null
#  user_id       :integer          not null
#

class Lead < ApplicationRecord
  belongs_to :operator
  belongs_to :user
  belongs_to :ahoy_visit, class_name: "Ahoy::Visit"

  after_create :set_status

  def set_status
    if status.blank?
      update(status: "open")
    end
  end
end
