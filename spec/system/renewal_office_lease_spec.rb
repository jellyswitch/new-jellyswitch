require "rails_helper"

RSpec.describe "Renewal Office Lease", type: :system do
  include ApplicationHelper
  fixtures :plans

  let(:admin) { create(:user, role: User::ADMIN) }
  let(:office) { create(:office, name: "Office A") }
  let!(:office_lease) { create(:office_lease, office: office, start_date: Date.today, end_date: Date.today + 20.days) }
  let(:lease_plan) { plans(:cowork_tahoe_office_lease_plan) }

  context "when the office lease is able to be renewed" do
    before do
      StripeMock.start

      @product = Stripe::Product.create({ name: "Cowork Tahoe Office Lease Plan", type: "service" })

      @stripe_plan = StripeMock.create_test_helper.create_plan(
        amount: lease_plan.amount_in_cents,
        interval: lease_plan.stripe_interval,
        interval_count: lease_plan.stripe_interval_count,
        product: @product.id,
        currency: "usd",
        id: lease_plan.plan_slug,
      )

      lease_plan.update(stripe_plan_id: @stripe_plan.id)

      log_in admin
      visit office_path(office)
    end

    it "new lease will appear in the Upcoming Lease section of the office" do
      click_on "Manage active lease"
      wait_for_turbo

      click_on "Setup Renewal Lease"
      wait_for_turbo

      pricing_field_name = "office_lease[subscription_attributes][plan_attributes][amount_in_cents]"
      # Assert the form is pre-populated with the current lease details
      expect(page).to have_field("office_lease[organization_id]", with: office_lease.organization_id)
      expect(page).to have_field("office_lease[office_id]", with: office.id)
      expect(page).to have_field(pricing_field_name, with: office_lease.subscription.plan.amount_in_cents)

      # Assert starting date matches the end date of the current lease
      expect(page).to have_field("office_lease[start_date(2i)]", with: office_lease.end_date.month)
      expect(page).to have_field("office_lease[start_date(3i)]", with: office_lease.end_date.day)
      expect(page).to have_field("office_lease[start_date(1i)]", with: office_lease.end_date.year)

      fill_in pricing_field_name, with: 12000

      # TODO - Add a test for setup stripe mock
    end
  end
end
