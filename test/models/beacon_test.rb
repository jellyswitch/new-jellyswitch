# == Schema Information
#
# Table name: beacons
#
#  id           :bigint(8)        not null, primary key
#  available    :boolean          default(TRUE), not null
#  battery_pct  :integer
#  installed_at :datetime
#  last_seen_at :datetime
#  major        :integer          not null
#  minor        :integer          not null
#  name         :string           not null
#  notes        :text
#  uuid         :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  door_id      :bigint(8)
#  location_id  :bigint(8)        not null
#  operator_id  :integer          default(1), not null
#
# Indexes
#
#  index_beacons_on_door_id                    (door_id)
#  index_beacons_on_location_id                (location_id)
#  index_beacons_on_operator_id                (operator_id)
#  index_beacons_on_operator_uuid_major_minor  (operator_id,uuid,major,minor) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (door_id => doors.id)
#  fk_rails_...  (location_id => locations.id)
#
require "test_helper"

class BeaconTest < ActiveSupport::TestCase
  setup do
    @beacon = beacons(:cowork_tahoe_front_door_beacon)
  end

  test "fixture is valid" do
    assert @beacon.valid?
  end

  test "requires name, uuid, major, minor" do
    beacon = Beacon.new(operator: @beacon.operator, location: @beacon.location)
    assert_not beacon.valid?
    assert_includes beacon.errors[:name],  "can't be blank"
    assert_includes beacon.errors[:uuid],  "can't be blank"
    assert_includes beacon.errors[:major], "can't be blank"
    assert_includes beacon.errors[:minor], "can't be blank"
  end

  test "major and minor must be in 0..65535" do
    @beacon.major = -1
    assert_not @beacon.valid?
    @beacon.major = 65_536
    assert_not @beacon.valid?
    @beacon.major = 1
    @beacon.minor = 70_000
    assert_not @beacon.valid?
  end

  test "battery_pct must be 0..100 when present" do
    @beacon.battery_pct = 101
    assert_not @beacon.valid?
    @beacon.battery_pct = -1
    assert_not @beacon.valid?
    @beacon.battery_pct = nil
    assert @beacon.valid?
  end

  test "uuid+major+minor is unique per operator" do
    duplicate = @beacon.dup
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:uuid], "has already been taken"
  end

  test "available scope excludes soft-deleted beacons" do
    @beacon.update!(available: false)
    assert_not_includes Beacon.available, @beacon
    assert_includes Beacon.unavailable, @beacon
  end

  test "low_battery? returns true at or below 20%" do
    @beacon.battery_pct = 21
    assert_not @beacon.low_battery?
    @beacon.battery_pct = 20
    assert @beacon.low_battery?
    @beacon.battery_pct = nil
    assert_not @beacon.low_battery?
  end

  test "stale? returns true when last_seen_at is nil or older than 24h" do
    @beacon.last_seen_at = nil
    assert @beacon.stale?
    @beacon.last_seen_at = 25.hours.ago
    assert @beacon.stale?
    @beacon.last_seen_at = 5.minutes.ago
    assert_not @beacon.stale?
  end

  test "door is optional" do
    @beacon.door = nil
    assert @beacon.valid?
  end
end
