FactoryBot.define do
  factory :operator do
    sequence(:name) { |n| "jellywork-#{n}" }
    snippet { Faker::TvShows::GameOfThrones.quote }
    wifi_name { name }
    wifi_password { Faker::Ancient.god }
    building_address { Faker::Address.full_address }
    contact_name { Faker::Name.unique.name }
    contact_email { Faker::Internet.unique.safe_email }
    contact_phone { Faker::PhoneNumber.phone_number }
    square_footage { 2000 }
    subdomain { "placeholder" }
    stripe_user_id { ENV['STRIPE_ACCOUNT_ID'] }
  end
end
