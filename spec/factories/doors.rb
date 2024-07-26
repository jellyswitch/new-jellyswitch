FactoryBot.define do
  factory :door do
    sequence(:name) { |n| "Door #{n}" }
    sequence(:slug) { |n| "door-#{n}" }
    available { true }
    private { false }
    sequence(:kisi_id) { |n| n }

    operator { Operator.find_by(name: "Cowork Tahoe") || association(:operator) }
    location_id { Location.find_by(name: "Cowork Tahoe").id || create(:location).id }
  end
end
