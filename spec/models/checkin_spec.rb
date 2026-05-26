# == Schema Information
#
# Table name: checkins
#
#  id            :bigint(8)        not null, primary key
#  billable_type :string
#  datetime_in   :timestamptz      not null
#  datetime_out  :timestamptz
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  billable_id   :bigint(8)
#  invoice_id    :integer
#  location_id   :integer          not null
#  user_id       :integer          not null
#
# Indexes
#
#  index_checkins_on_billable_type_and_billable_id  (billable_type,billable_id)
#  index_checkins_on_location_id                    (location_id)
#
require "rails_helper"

RSpec.describe Checkin, type: :model do
  describe "activity logging" do
    let(:user) { create(:user) }
    let(:location) { Location.first }

    it "creates exactly one :checkin Activity on create" do
      user # force creation so the user-signup Activity is outside the expect block
      expect {
        create(:checkin, user: user, location: location)
      }.to change(Activity.where(kind: "checkin"), :count).by(1)
    end

    it "associates the activity with the user, operator, and checkin" do
      checkin = create(:checkin, user: user, location: location)
      activity = Activity.last

      expect(activity.user).to eq(user)
      expect(activity.operator).to eq(location.operator)
      expect(activity.subject).to eq(checkin)
    end

    it "denormalizes location_name and datetime_in into payload" do
      checkin = create(:checkin, user: user, location: location)
      activity = Activity.last

      expect(activity.payload["location_name"]).to eq(location.name)
      expect(activity.payload["datetime_in"]).to be_present
    end
  end
end
