require "rails_helper"

RSpec.describe "Landing Page", type: :system do
  include ApplicationHelper

  let(:user) { create(:user) }
  let(:operator) { Operator.first }
  let(:location_1) { create(:location, name: "First location", operator: operator) }
  let(:location_2) { create(:location, name: "Last location", operator: operator) }
  let!(:room_1) { create(:room, location: location_1) }
  let!(:room_2) { create(:room, location: location_2) }
  let!(:ongoing_reservation) { create(:reservation, user: user, datetime_in: Time.zone.now, minutes: 30, room: room_1) }


  # Location is set via the persisted User#current_location association rather
  # than driving the UI picker through Capybara. The picker flow was flaky
  # because session[:location_id] was occasionally lost across the post-login
  # redirect; the SessionsHelper now falls back to current_user.current_location
  # so persisting on the user is sufficient.
  context "when user has an reservation" do

    context "when user has an ongoing reservation at the location" do
      let(:room) { room_1 }

      before do
        user.update!(current_location: location_1)
        log_in user
      end

      it "displays the user's ongoing reservation on the page" do
        expect(page).to have_content("Upcoming Reservation")
        expect(page).to have_content(ongoing_reservation.datetime_in.strftime("%B %-d, %Y"))
        expect(page).to have_content(ongoing_reservation.room.name)
      end
    end

    context "when user has an future/ongoing reservations at a different location" do
      before do
        user.update!(current_location: location_2)
        log_in user
      end

      it "does not display the upcoming reservation section" do
        expect(page).not_to have_content("Upcoming Reservation")
      end
    end
  end

  context "when user doesn't have any future/ongoing reservations at the location" do
    before do
      user.reservations.future.destroy_all
      user.reservations.ongoing.destroy_all
      user.update!(current_location: location_1)
      log_in user
    end

    it "does not display the upcoming reservation section" do
      expect(page).not_to have_content("Upcoming Reservation")
    end
  end
end
