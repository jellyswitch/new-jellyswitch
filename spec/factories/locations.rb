# == Schema Information
#
# Table name: locations
#
#  id                     :bigint(8)        not null, primary key
#  billing_state          :string
#  building_address       :string
#  city                   :string
#  contact_email          :string
#  contact_name           :string
#  contact_phone          :string
#  name                   :string
#  snippet                :string
#  square_footage         :integer
#  state                  :string
#  stripe_access_token    :string
#  stripe_publishable_key :string
#  stripe_refresh_token   :string
#  wifi_name              :string
#  wifi_password          :string
#  zip                    :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  operator_id            :bigint(8)        not null
#  stripe_user_id         :string
#
# Indexes
#
#  index_locations_on_operator_id     (operator_id)
#  index_locations_on_state_and_city  (state,city)
#  index_locations_on_zip             (zip)
#
# Foreign Keys
#
#  fk_rails_...  (operator_id => operators.id)
#

FactoryBot.define do
  factory :location do
    name { "MyString" }
    billing_state { "MyString" }
    building_address { "MyString" }
    contact_email { "MyString" }
    contact_name { "MyString" }
    contact_phone { "MyString" }
    snippet { "MyString" }
    square_footage { 1 }
    stripe_access_token { "MyString" }
    stripe_publishable_key { "MyString" }
    stripe_refresh_token { "MyString" }
    wifi_name { "MyString" }
    wifi_password { "MyString" }
    stripe_user_id { "MyString" }
  end
end
