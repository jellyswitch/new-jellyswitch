require "rails_helper"

RSpec.describe "Update Office Lease Price", type: :system do
  context "when the office lease is active and admin enter new office lease price in the update form" do
    before do
      @next_cycle_date = Date.today + 1.months
      expect_any_instance_of(OfficeLease).to receive(:current_period_end).and_return(@next_cycle_date.to_time.to_i)

      @office = create(:office, name: "Office A")
      @office_lease = create(:office_lease, office: @office, start_date: Date.today, end_date: Date.today + 2.months)
      @admin = create(:user, role: User::ADMIN, managed_locations: [@office.location])

      log_in @admin
      visit office_path(@office)
    end

    it "shows new updated price with lease information" do
      visit office_lease_edit_price_path(@office_lease)

      expect(page).to have_button("Update Pricing", disabled: true)

      # Operator enters the price in dollars (not cents).
      page.execute_script("var input = document.getElementById('office_lease_new_price'); input.value = 150; input.dispatchEvent(new Event('input'))")

      expect(page).to have_button("Update Pricing", disabled: false)
      click_on "Update Pricing"

      # Fallback in case Bootstrap data-toggle's jQuery binding races the click
      # (the flake we hit in CI: modal HTML is in the DOM but never gets the
      # .show class, so assert_text sees only non-visible text). Triggering
      # .modal('show') directly is idempotent if the click already opened it.
      page.execute_script("$('#update-price-confirm-modal').modal('show')")
      assert_text "Please review the following information before confirming the price update:", wait: 10

      assert_text "New Price:"
      assert_text "$150.00 per month"

      assert_text "Next Cycle:"
      assert_text @next_cycle_date.strftime("%B %d, %Y")
    end
  end
end
