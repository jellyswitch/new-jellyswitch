require "rails_helper"

# Bug fix: on the office detail page the leasee's name was rendered as a blue
# (text-info) <span> that looked clickable but wasn't. It should link through to
# the group (organization) or individual (member) holding the active lease.
RSpec.describe "Office detail leasee link", type: :system do
  let(:office) { create(:office, name: "Office 203") }

  context "for an organization (group) lease" do
    let(:organization) { create(:organization, name: "Iron Gate Realty") }
    let!(:office_lease) do
      create(:office_lease,
        office: office,
        organization: organization,
        start_date: Date.today - 1.day,
        end_date: Date.today + 1.year)
    end
    let(:admin) { create(:user, role: User::ADMIN, managed_locations: [office_lease.location]) }

    it "links the leasee name to the organization" do
      log_in admin
      visit office_path(office)

      expect(page).to have_link("Iron Gate Realty", href: organization_path(organization))
    end
  end

  context "for an individual (member) lease" do
    let(:member) { create(:user, name: "Jane Member") }
    let!(:office_lease) do
      create(:office_lease,
        office: office,
        organization: nil,
        user: member,
        start_date: Date.today - 1.day,
        end_date: Date.today + 1.year)
    end
    let(:admin) { create(:user, role: User::ADMIN, managed_locations: [office_lease.location]) }

    it "links the leasee name to the member" do
      log_in admin
      visit office_path(office)

      expect(page).to have_link("Jane Member", href: user_path(member))
    end
  end
end
