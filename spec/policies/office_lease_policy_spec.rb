require "rails_helper"

RSpec.describe OfficeLeasePolicy do
  let(:operator)     { create(:operator) }
  let(:location)     { create(:location, operator: operator, offices_enabled: true) }
  let(:owner_member) { create(:user, operator: operator, original_location: location) }
  let(:org)          { create(:organization, operator: operator, owner: owner_member) }
  let(:lease)        { create(:office_lease, operator: operator, location: location, organization: org) }
  let(:admin)        { create(:user, operator: operator, role: "superadmin", original_location: location) }

  def can_terminate_now?(user)
    OfficeLeasePolicy.new(UserContext.new(user, operator, location), lease).destroy_office_lease_now?
  end

  describe "#destroy_office_lease_now? — terminating a lease early is staff-only" do
    it "does NOT let a non-staff organization owner terminate the lease immediately" do
      expect(org.owner).to eq(owner_member) # sanity: this member owns THIS org
      expect(can_terminate_now?(owner_member)).to be false
    end

    it "lets staff (superadmin) terminate the lease immediately" do
      expect(can_terminate_now?(admin)).to be true
    end
  end
end
