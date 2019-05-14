# == Schema Information
#
# Table name: checkins
#
#  id           :bigint(8)        not null, primary key
#  datetime_in  :datetime         not null
#  datetime_out :datetime
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  invoice_id   :integer
#  location_id  :integer          not null
#  user_id      :integer          not null
#

require 'rails_helper'

RSpec.describe Checkin, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
