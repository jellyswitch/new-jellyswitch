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

      it "converts the dollar amount entered by the operator into cents" do
        expect(Billing::Leasing::UpdateLeasePrice).to receive(:call)
          .with(hash_including(new_price_in_cents: 15000))
          .and_return(result)

        put :update_price, params: { office_lease_id: office_lease.id, office_lease: { new_price: "150" } }
      end

      it "handles fractional dollar amounts" do
        expect(Billing::Leasing::UpdateLeasePrice).to receive(:call)
          .with(hash_including(new_price_in_cents: 15050))
          .and_return(result)

        put :update_price, params: { office_lease_id: office_lease.id, office_lease: { new_price: "150.50" } }
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

  describe "#create" do
    let(:location) { office_lease.location }
    let(:organization) { office_lease.organization }
    let(:office) { create(:office, location: location, operator: location.operator) }

    before do
      allow(controller).to receive(:current_location).and_return(location)
      allow(controller).to receive(:current_tenant).and_return(location.operator)
    end

    def create_params(amount:, deposit:)
      {
        office_lease: {
          organization_id: organization.id,
          office_id: office.id,
          start_date: Date.today,
          end_date: Date.today + 1.year,
          initial_invoice_date: Date.today + 1.day,
          deposit_amount_in_cents: deposit,
          subscription_attributes: {
            plan_attributes: {
              name: "Office Lease Plan",
              plan_type: "lease",
              interval: "monthly",
              amount_in_cents: amount,
            },
          },
        },
      }
    end

    it "converts the dollar amount and deposit entered by the operator into cents" do
      captured = nil
      expect(Billing::Leasing::CreateOfficeLease).to receive(:call) do |args|
        captured = args[:office_lease]
        double(success?: true, office_lease: office_lease)
      end

      post :create, params: create_params(amount: "579", deposit: "250")

      expect(captured.subscription.plan.amount_in_cents).to eq(57_900)
      expect(captured.deposit_amount_in_cents).to eq(25_000)
    end

    it "handles fractional dollar amounts" do
      captured = nil
      expect(Billing::Leasing::CreateOfficeLease).to receive(:call) do |args|
        captured = args[:office_lease]
        double(success?: true, office_lease: office_lease)
      end

      post :create, params: create_params(amount: "579.50", deposit: "12.34")

      expect(captured.subscription.plan.amount_in_cents).to eq(57_950)
      expect(captured.deposit_amount_in_cents).to eq(1_234)
    end
  end

  describe "#mark_deposit_invoiced" do
    it "stamps deposit_invoiced_at without charging anything" do
      expect(Billing::Leasing::ChargeDeposit).not_to receive(:call)

      post :mark_deposit_invoiced, params: { office_lease_id: office_lease.id }

      expect(office_lease.reload.deposit_invoiced_at).to be_present
      expect(flash[:success]).to be_present
    end
  end

  describe "#charge_deposit" do
    it "runs ChargeDeposit and reports success once the deposit is invoiced" do
      expect(Billing::Leasing::ChargeDeposit).to receive(:call) do |args|
        args[:office_lease].update!(deposit_invoiced_at: Time.current)
      end

      post :charge_deposit, params: { office_lease_id: office_lease.id }

      expect(flash[:success]).to match(/deposit invoice/i)
    end

    it "reports a recoverable error when the deposit still wasn't invoiced" do
      allow(Billing::Leasing::ChargeDeposit).to receive(:call) # no-op → stays nil

      post :charge_deposit, params: { office_lease_id: office_lease.id }

      expect(office_lease.reload.deposit_invoiced_at).to be_nil
      expect(flash[:error]).to be_present
    end
  end
end
