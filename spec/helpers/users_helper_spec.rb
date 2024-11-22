require 'rails_helper'

RSpec.describe UsersHelper, type: :helper do
  let(:operator) { Operator.first }
  let(:location) { operator.locations.first }
  let(:other_location) { create :location, operator: operator }

  let!(:approved_location_user) { create :user, name: "test user", operator: operator, original_location: location, approved: true }
  let!(:approved_location_another_user) { create :user, name: "another user", operator: operator, original_location: location, approved: true }
  let!(:unapproved_location_user) { create :user, operator: operator, original_location: location, approved: false }
  let!(:approved_other_location_user) { create :user, operator: operator, original_location: other_location, approved: true }
  let!(:archived_location_user) { create :user, operator: operator, original_location: location, approved: true, archived: true }

  before do
    allow(helper).to receive(:current_tenant).and_return(operator)
    allow(helper).to receive(:current_location).and_return(location)
    User.reindex
  end

  describe "#find_user" do
    context "when current user is viewing self" do
      it "sets @user to current user" do
        allow(helper).to receive(:current_user).and_return(approved_location_user)
        allow(helper).to receive(:params).and_return(id: approved_location_user.id)
        helper.find_user
        expect(helper.instance_variable_get(:@user)).to eq(approved_location_user)
      end
    end

    context "when current user is viewing another user" do
      context "when current user is not at the same location as the user" do
        it "raises an error" do
          allow(helper).to receive(:current_user).and_return(approved_location_user)
          allow(helper).to receive(:params).and_return(id: approved_other_location_user.id)

          expect { helper.find_user(:id) }.to raise_error(ActiveRecord::RecordNotFound)
        end
      end

      context "when current user is at the same location as the user" do
        it "sets @user to another user" do
          allow(helper).to receive(:current_user).and_return(approved_location_user)
          allow(helper).to receive(:params).and_return(id: approved_location_another_user.id)
          helper.find_user(:id)
          expect(helper.instance_variable_get(:@user)).to eq(approved_location_another_user)
        end
      end
    end
  end

  describe '#find_approved_users' do
    context 'when query is present' do
      it 'returns paginated approved users based on query' do
        expect(helper.find_approved_users("another")[1]).to eq([approved_location_another_user])
      end
    end

    context 'when query is not present' do
      it 'returns paginated approved users' do
        expect(helper.find_approved_users[1]).to match_array([approved_location_user, approved_location_another_user])
      end
    end
  end

  describe '#find_unapproved_users' do
    it 'returns unapproved users' do
      expect(helper.find_unapproved_users).to eq([unapproved_location_user])
    end
  end

  describe '#set_unapproved_users' do
    it 'sets @users to unapproved users' do
      helper.set_unapproved_users
      expect(helper.instance_variable_get(:@users)).to eq([unapproved_location_user])
    end
  end

  describe '#find_archived_users' do
    it 'returns archived users' do
      expect(helper.find_archived_users).to eq([archived_location_user])
    end
  end

  describe '#set_archived_users' do
    it 'sets @pagy and @users to paginated archived users' do
      helper.set_archived_users
      expect(helper.instance_variable_get(:@users)).to eq([archived_location_user])
    end
  end
end