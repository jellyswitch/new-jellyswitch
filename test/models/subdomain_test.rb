# == Schema Information
#
# Table name: subdomains
#
#  id         :bigint(8)        not null, primary key
#  in_use     :boolean          default(FALSE), not null
#  subdomain  :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#

require 'test_helper'

class SubdomainTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
