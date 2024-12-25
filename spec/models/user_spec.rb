require 'rails_helper'

RSpec.describe User, type: :model do
  let(:operator) { create(:operator) }
  let(:location) { create(:location, operator: operator) }

  describe 'validations' do
    it { should validate_presence_of(:email) }
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:password).on(:create) }
    it { should validate_length_of(:password).is_at_least(6).on(:create) }
  end

  describe 'associations' do
    it { should have_many(:announcements) }
    it { should have_many(:checkins) }
    it { should have_many(:child_profiles) }
    it { should have_many(:childcare_reservations).through(:child_profiles) }
    it { should have_many(:day_passes) }
    it { should have_many(:door_punches) }
    it { should have_many(:events) }
    it { should belong_to(:operator) }
    it { should belong_to(:organization).optional }
    it { should belong_to(:original_location).class_name('Location').optional }
    it { should belong_to(:current_location).class_name('Location').optional }
    it { should have_many(:location_managements) }
    it { should have_many(:managed_locations).through(:location_managements) }
    it { should have_many(:user_payment_profiles) }
  end

  describe 'scopes' do
    let!(:approved_user) { create(:user, approved: true, operator: operator) }
    let!(:unapproved_user) { create(:user, approved: false, operator: operator) }
    let!(:archived_user) { create(:user, archived: true, operator: operator) }
    let!(:admin_user) { create(:user, role: 'admin', operator: operator) }

    it 'returns approved users' do
      expect(User.approved).to include(approved_user)
      expect(User.approved).not_to include(unapproved_user)
    end

    it 'returns unapproved users' do
      expect(User.unapproved).to include(unapproved_user)
      expect(User.unapproved).not_to include(approved_user)
    end

    it 'returns archived users' do
      expect(User.archived).to include(archived_user)
      expect(User.archived).not_to include(approved_user)
    end

    it 'returns visible users' do
      expect(User.visible).to include(approved_user)
      expect(User.visible).not_to include(archived_user)
    end
  end

  describe 'role management' do
    let(:user) { create(:user, operator: operator) }

    it 'has valid roles' do
      expect(User.roles).to contain_exactly(
        'unassigned',
        'community-manager',
        'general-manager',
        'admin',
        'superadmin'
      )
    end

    it 'defaults to unassigned role' do
      expect(user.role).to eq('unassigned')
    end
  end

  describe '#payment_profile_for_location' do
    let(:user) { create(:user, operator: operator) }
    let(:location) { create(:location, operator: operator) }

    it 'creates a new payment profile if none exists' do
      expect {
        user.payment_profile_for_location(location)
      }.to change(UserPaymentProfile, :count).by(1)
    end

    it 'returns existing payment profile if one exists' do
      profile = create(:user_payment_profile, user: user, location: location)
      expect(user.payment_profile_for_location(location)).to eq(profile)
    end
  end

  describe 'authentication' do
    let(:user) { create(:user, operator: operator) }

    it 'creates a reset digest when requesting password reset' do
      expect {
        user.create_reset_digest
      }.to change(user, :reset_digest)
        .and change(user, :reset_sent_at)
    end

    it 'determines if password reset is expired' do
      user.update(reset_sent_at: 3.hours.ago)
      expect(user.password_reset_expired?).to be true

      user.update(reset_sent_at: 1.hour.ago)
      expect(user.password_reset_expired?).to be false
    end
  end

  describe 'permissions' do
    let(:operator) { create(:operator) }
    let(:location) { create(:location, operator: operator) }
    let(:user) { create(:user, operator: operator, current_location: location) }
    let(:organization) { create(:organization) }

    describe '#allowed_in?' do
      context 'when user has building access membership' do
        before do
          allow_any_instance_of(Permissions).to receive(:has_building_access_membership?).and_return(true)
        end

        it 'returns true' do
          expect(user.allowed_in?(location)).to be true
        end
      end

      context 'when user has active day pass' do
        before do
          allow_any_instance_of(Permissions).to receive(:has_active_day_pass_at_location?).and_return(true)
        end

        it 'returns true' do
          expect(user.allowed_in?(location)).to be true
        end
      end

      context 'when user is checked in' do
        before do
          allow_any_instance_of(Permissions).to receive(:checked_in?).and_return(true)
        end

        it 'returns true' do
          expect(user.allowed_in?(location)).to be true
        end
      end
    end

    describe '#should_charge_for_reservation?' do
      before do
        allow(operator).to receive(:production?).and_return(true)
      end

      context 'when user is a member' do
        before do
          allow_any_instance_of(Permissions).to receive(:member?).and_return(true)
        end

        it 'returns false' do
          expect(user.should_charge_for_reservation?(location)).to be false
        end
      end

      context 'when user has no special status' do
        it 'returns true' do
          expect(user.should_charge_for_reservation?(location)).to be true
        end
      end
    end

    describe '#member_at_location?' do
      context 'when user has active subscription at location' do
        before do
          allow_any_instance_of(Permissions).to receive(:has_active_subscription?).and_return(true)
          user.current_location = location
        end

        it 'returns true' do
          expect(user.member_at_location?(location)).to be true
        end
      end

      context 'when user is at different location' do
        before do
          user.current_location = create(:location)
        end

        it 'returns false' do
          expect(user.member_at_location?(location)).to be false
        end
      end
    end

    describe '#has_active_subscription_at_location?' do
      let(:plan) { create(:plan, location: location) }

      context 'when user has active subscription' do
        before do
          create(:subscription, subscribable: user, plan: plan, active: true)
        end

        it 'returns true' do
          expect(user.has_active_subscription_at_location?(location)).to be true
        end
      end

      context 'when user has no subscription' do
        it 'returns false' do
          expect(user.has_active_subscription_at_location?(location)).to be false
        end
      end
    end

    describe '#has_building_access?' do
      context 'when user is superadmin' do
        before { user.update(role: 'superadmin') }

        it 'returns true' do
          expect(user.has_building_access?(location)).to be true
        end
      end

      context 'when user has building access membership' do
        before do
          allow_any_instance_of(Permissions).to receive(:has_building_access_membership?).and_return(true)
        end

        it 'returns true' do
          expect(user.has_building_access?(location)).to be true
        end
      end
    end

    describe '#has_active_day_pass?' do
      context 'when user has day pass for current day' do
        before do
          create(:day_pass, user: user, day: Date.current)
        end

        it 'returns true' do
          expect(user.has_active_day_pass?).to be true
        end
      end

      context 'when user has no day pass' do
        it 'returns false' do
          expect(user.has_active_day_pass?).to be false
        end
      end
    end

    describe '#admin_or_manager?' do
      context 'when user is admin of location' do
        before do
          allow(user).to receive(:admin_of_location?).with(location).and_return(true)
        end

        it 'returns true' do
          expect(user.admin_or_manager?(location)).to be true
        end
      end

      context 'when user is community manager' do
        before do
          allow(user).to receive(:community_manager_of_location?).with(location).and_return(true)
        end

        it 'returns true' do
          expect(user.admin_or_manager?(location)).to be true
        end
      end

      context 'when user has no special role' do
        it 'returns false' do
          expect(user.admin_or_manager?(location)).to be false
        end
      end
    end
  end
end