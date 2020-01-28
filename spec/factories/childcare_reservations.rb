FactoryBot.define do
  factory :childcare_reservation do
    childcare_slot_id { 1 }
    child_profile_id { 1 }
    date { "2020-01-28" }
  end
end
