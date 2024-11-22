require "rails_helper"

RSpec.describe Operator::OfficeLeasesController, type: :controller do
  let!(:office_lease) { create(:office_lease, start_date: Date.today - 1.month, end_date: Date.today + 1.month) }
  let!(:operator) { create(:operator) }
  let!(:admin) { create(:user, role: User::ADMIN, managed_locations: [office_lease.location]) }

  before do
    allow(controller).to receive(:current_user).and_return(admin)
    allow_any_instance_of(OfficeLease).to receive(:subscription_active?).and_return(true)
  end

  describe "#update_price" do
    context "when the update price is successful" do
      let(:result) { double(success?: true) }

      it "sets and success flash message and redirects to the office lease path" do
        expect(Billing::Leasing::UpdateLeasePrice).to receive(:call).and_return(result)
        put :update_price, params: { office_lease_id: office_lease.id, office_lease: { new_price: 100 } }

        expect(flash[:notice]).to eq("Lease price updated successfully.")
        expect(response).to redirect_to(office_lease_path(office_lease))
      end
    end

    context "when the update price is fails" do
      let(:result) { double(success?: false, message: "Something went wrong!") }

      it "sets and error flash message and redirects to the office lease edit price path" do
        expect(Billing::Leasing::UpdateLeasePrice).to receive(:call).and_return(result)

        put :update_price, params: { office_lease_id: office_lease.id, office_lease: { new_price: -100 } }

        expect(flash[:error]).to eq("Something went wrong!")
        expect(response).to redirect_to(office_lease_edit_price_path(office_lease))
      end
    end
  end
end
