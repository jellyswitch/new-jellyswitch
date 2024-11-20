FactoryBot.define do
  factory :tracking_pixel do
    name { "Google Analytics" }
    script { "UA-12345678-1" }
    position { :body }
    association :operator
    association :location
  end
end