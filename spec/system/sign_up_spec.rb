require "rails_helper"

RSpec.describe "Sign up / Registration flow", type: :system do
  include ApplicationHelper

  let(:operator) { Operator.first }
  let(:location) { Location.first }
  let!(:other_location) { create(:location, name: "Other location", operator: operator) }

  context "user signs up specifying a different location than the default" do
    before do
      visit root_path
      switch_to_location location
    end

    it "creates user account and switches to the location he chooses" do
      visit root_path
      click_link "Sign Up"
      wait_for_turbo

      fill_in "Name", with: "New User"
      fill_in "Email", with: "new_user@email.com"
      fill_in "Password", with: "password"
      fill_in "Confirm password", with: "password"
      select other_location.name, from: "Main location"
      click_button "Get Started"
      wait_for_turbo

      expect(page).to have_content other_location.name
      expect(page).to have_content "Please select an option below."

      # user sees his current location in account info
      click_link "My Account"
      wait_for_turbo
      expect(page.find(".original-location")).to have_content(other_location.name)
      expect(page.find(".current-location")).to have_content(other_location.name)

      # user switches to another location
      switch_to_location location
      click_link "My Account"
      wait_for_turbo
      expect(page.find(".original-location")).to have_content(other_location.name)
      expect(page.find(".current-location")).to have_content(location.name)
    end
  end
end

