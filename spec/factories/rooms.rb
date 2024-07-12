FactoryBot.define do
  factory :room do
    sequence(:name) { |n| "Meeting Room #{n}" }
    description { "Small Meeting Room with a Table & 4 Chairs" }
    whiteboard { false }
    av { false }
    capacity { 4 }
    sequence(:slug) { |n| "meeting-room-#{n}" }
    visible { true }
    square_footage { 60 }
    rentable { true }
    hourly_rate_in_cents { 0 }
    credit_cost { 5 }
    allow_shorter_reservation_duration { true }

    operator { Operator.find_by(name: "Cowork Tahoe") || association(:operator) }
    location { Location.find_by(name: "Cowork Tahoe") }
  end
end
