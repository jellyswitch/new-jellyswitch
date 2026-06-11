require 'rails_helper'

RSpec.describe Operator::CompDaysController, type: :controller do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }
  let(:admin)    { create(:user, operator: operator, role: "superadmin", original_location: location) }
  let(:member)   { create(:user, operator: operator, original_location: location) }

  before do
    allow(controller).to receive(:current_location).and_return(location)
    allow(controller).to receive(:current_user).and_return(admin)
    request.host = "#{operator.subdomain}.lvh.me"
  end

  it "comps a day for the member at the current location, attributed to the granting admin" do
    expect {
      post :create, params: { user_id: member.id, reason: "card reader was down" }
    }.to change(CompDay, :count).by(1)

    comp = CompDay.last
    expect(comp.user).to eq(member)
    expect(comp.location).to eq(location)
    expect(comp.operator).to eq(operator)
    expect(comp.granted_by).to eq(admin)
    expect(comp.occurred_on).to eq(Date.current)
    expect(comp.reason).to eq("card reader was down")
  end

  it "does not let a non-manager comp a day" do
    allow(controller).to receive(:current_user).and_return(member)
    expect {
      post :create, params: { user_id: member.id }
    }.not_to change(CompDay, :count)
  end
end
