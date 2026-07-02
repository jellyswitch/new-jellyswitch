# == Schema Information
#
# Table name: rooms
#
#  id                                 :bigint(8)        not null, primary key
#  allow_shorter_reservation_duration :boolean          default(TRUE), not null
#  archived                           :boolean          default(FALSE), not null
#  capacity                           :integer          default(1), not null
#  credit_cost                        :integer          default(0), not null
#  description                        :text
#  features                           :text             default([]), is an Array
#  hourly_rate_in_cents               :integer          default(0), not null
#  include_with_day_pass              :boolean          default(FALSE), not null
#  name                               :string           not null
#  rentable                           :boolean          default(FALSE), not null
#  slug                               :string
#  square_footage                     :integer          default(0), not null
#  visible                            :boolean          default(TRUE), not null
#  created_at                         :datetime         not null
#  updated_at                         :datetime         not null
#  location_id                        :bigint(8)
#  operator_id                        :integer          default(1), not null
#
# Indexes
#
#  index_rooms_on_archived     (archived)
#  index_rooms_on_location_id  (location_id)
#  index_rooms_on_operator_id  (operator_id)
#
# Foreign Keys
#
#  fk_rails_...  (location_id => locations.id)
#
FactoryBot.define do
  factory :room do
    sequence(:name) { |n| "Meeting Room #{n}" }
    description { "Small Meeting Room with a Table & 4 Chairs" }
    capacity { 4 }
    sequence(:slug) { |n| "meeting-room-#{n}" }
    visible { true }
    square_footage { 60 }
    rentable { true }
    hourly_rate_in_cents { 0 }
    # Mirror the migration backfill: $0 (call) rooms count toward the day-pass
    # included-minutes bucket; priced rooms don't. ADR 0012.
    include_with_day_pass { (hourly_rate_in_cents || 0).to_i == 0 }
    credit_cost { 5 }
    allow_shorter_reservation_duration { true }

    operator { Operator.find_by(name: "Cowork Tahoe") || association(:operator) }
    location { Location.find_by(name: "Cowork Tahoe") }
  end
end
