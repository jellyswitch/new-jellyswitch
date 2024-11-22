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

    # New traits for calendar testing
    trait :morning do
      datetime_in { Time.current.change(hour: 9) }
    end

    trait :afternoon do
      datetime_in { Time.current.change(hour: 14) }
    end

    trait :evening do
      datetime_in { Time.current.change(hour: 16) }
    end

    trait :next_day do
      datetime_in { Time.current.tomorrow.change(hour: 10) }
    end
  end
end