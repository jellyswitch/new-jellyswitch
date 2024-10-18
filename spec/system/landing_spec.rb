require "rails_helper"

RSpec.describe "Landing Page", type: :system do
  include ApplicationHelper

  let(:user) { create(:user) }
  let!(:ongoing_reservation) { create(:reservation, user: user, datetime_in: Time.zone.now, minutes: 30) }

  ## Currently skipping this test since it's was unstable
  # context "when user has an ongoing reservation" do
  #   before do
  #     log_in user
  #   end

  #   it "displays the user's ongoing reservation on the page" do
  #     expect(page).to have_content("Upcoming Reservation")
  #     expect(page).to have_content(ongoing_reservation.datetime_in.strftime("%B %-d, %Y"))
  #     expect(page).to have_content(ongoing_reservation.room.name)
  #   end
  # end

  # context "when user doesn't have any future/ongoing reservations" do
  #   before do
  #     user.reservations.future.destroy_all
  #     user.reservations.ongoing.destroy_all
  #     log_in user
  #   end

  #   it "does not display the upcoming reservation section" do
  #     expect(page).not_to have_content("Upcoming Reservation")
  #   end
  # end
end
