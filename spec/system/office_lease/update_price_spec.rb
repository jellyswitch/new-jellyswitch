require "rails_helper"

RSpec.describe "Update Office Lease Price", type: :system do
  context "when the office lease is active and admin enter new office lease price in the update form" do
    before do
      @next_cycle_date = Date.today + 1.months
      expect_any_instance_of(OfficeLease).to receive(:current_period_end).and_return(@next_cycle_date.to_time.to_i)

      @admin = create(:user, role: User::ADMIN)
      @office = create(:office, name: "Office A")
      @office_lease = create(:office_lease, office: @office, start_date: Date.today, end_date: Date.today + 2.months)

      log_in @admin
      visit office_path(@office)
    end

    it "shows new updated price with lease information" do
      click_on "Manage active lease"
      click_on "Update Lease Pricing"
      wait_for_turbo

      expect(page).to have_button("Update Pricing", disabled: true)

      fill_in "office_lease[new_price]", with: 15000

      expect(page).to have_button("Update Pricing", disabled: false)
      click_on "Update Pricing"

      assert_text "Please review the following information before confirming the price update:"

      assert_text "New Price:"
      assert_text "$150.00 per month"

      assert_text "Next Cycle:"
      assert_text @next_cycle_date.strftime("%B %d, %Y")
    end
  end
end
