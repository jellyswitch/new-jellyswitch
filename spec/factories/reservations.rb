FactoryBot.define do
  factory :reservation do
    association :user
    association :room
    datetime_in { Time.current + 1.day }
    hours { 1 }
    minutes { 60 }
    credit_cost { 0 }
    cancelled { false }
    ended_early { false }
    paid { true }

    trait :cancelled do
      cancelled { true }
    end

    trait :ended_early do
      ended_early { true }
    end

    trait :past do
      datetime_in { 1.day.ago }
    end

    trait :future do
      datetime_in { 1.week.from_now }
    end
  end
end
