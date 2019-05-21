# == Schema Information
#
# Table name: operators
#
#  id                     :bigint(8)        not null, primary key
#  android_url            :string
#  approval_required      :boolean          default(TRUE), not null
#  billing_state          :string           default("demo"), not null
#  building_address       :string           default("not set"), not null
#  contact_email          :string
#  contact_name           :string
#  contact_phone          :string
#  day_pass_cost_in_cents :integer          default(2500), not null
#  email_enabled          :boolean          default(FALSE), not null
#  ios_url                :string
#  kisi_api_key           :string
#  name                   :string           not null
#  snippet                :string           default("Generic snippet about the space"), not null
#  square_footage         :integer          default(0), not null
#  stripe_access_token    :string
#  stripe_publishable_key :string
#  stripe_refresh_token   :string
#  subdomain              :string           not null
#  wifi_name              :string           default("not set"), not null
#  wifi_password          :string           default("not set"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  stripe_user_id         :string
#

require 'rails_helper'

RSpec.describe Operator, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
