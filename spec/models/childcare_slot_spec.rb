# == Schema Information
#
# Table name: childcare_slots
#
#  id          :bigint(8)        not null, primary key
#  deleted     :boolean
#  name        :string
#  week_day    :integer
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  location_id :integer
#

require 'rails_helper'

RSpec.describe ChildcareSlot, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
