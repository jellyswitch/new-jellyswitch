# == Schema Information
#
# Table name: operator_surveys
#
#  id                :bigint(8)        not null, primary key
#  location          :string
#  number_of_members :integer
#  operator_email    :string
#  operator_name     :string
#  space_name        :string
#  square_footage    :integer
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  operator_id       :integer
#  user_id           :integer
#

require 'test_helper'

class OperatorSurveyTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
