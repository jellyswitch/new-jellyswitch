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
    sequence(:name) { |n| "jellywork-#{n}" }
    snippet { Faker::TvShows::GameOfThrones.quote }
    wifi_name { name }
    wifi_password { Faker::Ancient.god }
    building_address { Faker::Address.full_address }
    contact_name { Faker::Name.unique.name }
    contact_email { Faker::Internet.unique.safe_email }
    contact_phone { Faker::PhoneNumber.phone_number }
    square_footage { 2000 }
    sequence(:subdomain) { |n| "test-#{n}" }
    stripe_user_id { ENV['STRIPE_ACCOUNT_ID'] }

    trait :with_offices do
      transient do
        office_count { 3 }
      end

      after(:create) do |operator, evaluator|
        create_list(:office, evaluator.office_count, operator: operator)
      end
    end
  end
end
