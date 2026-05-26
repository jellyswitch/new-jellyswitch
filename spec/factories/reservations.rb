# == Schema Information
#
# Table name: reservations
#
#  id                         :bigint(8)        not null, primary key
#  authorized_amount_in_cents :integer
#  cancelled                  :boolean          default(FALSE), not null
#  captured_amount_in_cents   :integer
#  captured_at                :datetime
#  credit_cost                :integer          default(0), not null
#  datetime_in                :timestamptz      not null
#  ended_early                :boolean          default(FALSE)
#  hours                      :integer          default(1), not null
#  minutes                    :integer          default(0), not null
#  note                       :text
#  paid                       :boolean
#  payment_failed_at          :datetime
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  recurring_reservation_id   :bigint(8)
#  room_id                    :integer          not null
#  stripe_payment_intent_id   :string
#  user_id                    :integer          not null
#
# Indexes
#
#  index_reservations_on_recurring_reservation_id  (recurring_reservation_id)
#  index_reservations_on_stripe_payment_intent_id  (stripe_payment_intent_id) UNIQUE
#
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
