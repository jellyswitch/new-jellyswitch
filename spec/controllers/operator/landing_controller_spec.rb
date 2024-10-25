require "rails_helper"

RSpec.describe Operator::LandingController, type: :controller do
  let!(:operator) { create(:operator) }
  let!(:location) { create(:location, operator: operator) }
  let!(:user) { create(:user) }
  let!(:ongoing_reservation) { create(:reservation, user: user, datetime_in: Time.zone.now, minutes: 30) }

  before do
    allow(controller).to receive(:current_user).and_return(user)
    allow(controller).to receive(:current_location).and_return(location)
  end

  describe "#home" do
    it "loads user reservations of the current location only" do
        expect_any_instance_of(User).to receive(:upcoming_or_ongoing_reservation).with(location.id).and_return(ongoing_reservation)
        get :home
        expect(assigns(:reservation)).to eq(ongoing_reservation)
    end
  end
end
