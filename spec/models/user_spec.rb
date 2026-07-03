# == Schema Information
#
# Table name: users
#
#  id                            :bigint(8)        not null, primary key
#  admin                         :boolean          default(FALSE), not null
#  always_allow_building_access  :boolean          default(FALSE), not null
#  android_token                 :string
#  approved                      :boolean          default(FALSE), not null
#  archived                      :boolean          default(FALSE), not null
#  bill_to_organization          :boolean          default(FALSE), not null
#  bio                           :text
#  card_added                    :boolean          default(FALSE), not null
#  childcare_reservation_balance :integer          default(0), not null
#  confirmation_sent_at          :datetime
#  confirmation_token            :string
#  credit_balance                :integer          default(0), not null
#  email                         :string           not null
#  email_bounced                 :boolean          default(FALSE), not null
#  email_confirmed               :boolean          default(FALSE), not null
#  email_opted_out               :boolean          default(FALSE), not null
#  home_city                     :string
#  home_latitude                 :decimal(10, 7)
#  home_longitude                :decimal(10, 7)
#  home_state                    :string
#  home_zip                      :string
#  inactive_dismissed_at         :datetime
#  ios_token                     :string
#  last_active_at                :datetime
#  linkedin                      :string
#  marketing_consent             :boolean          default(FALSE), not null
#  marketing_suppressed          :boolean          default(FALSE), not null
#  marketing_suppressed_reason   :string
#  name                          :string
#  out_of_band                   :boolean          default(FALSE), not null
#  password_digest               :string
#  phone                         :string
#  preferred_meeting_duration    :integer          default(60)
#  remember_digest               :string
#  reset_digest                  :string
#  reset_sent_at                 :datetime
#  role                          :string           default("unassigned"), not null
#  slug                          :string
#  superadmin                    :boolean          default(FALSE), not null
#  terms_accepted_at             :datetime
#  twitter                       :string
#  website                       :string
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  current_location_id           :integer
#  operator_id                   :integer          default(2), not null
#  organization_id               :integer
#  original_location_id          :integer
#  point_of_contact_id           :bigint(8)
#  preferred_room_id             :bigint(8)
#  stripe_customer_id            :string
#
# Indexes
#
#  index_users_on_home_state_and_home_city       (home_state,home_city)
#  index_users_on_home_zip                       (home_zip)
#  index_users_on_operator_home_state_home_city  (operator_id,home_state,home_city)
#  index_users_on_operator_id                    (operator_id)
#  index_users_on_point_of_contact_id            (point_of_contact_id)
#  index_users_on_preferred_room_id              (preferred_room_id)
#
# Foreign Keys
#
#  fk_rails_...  (point_of_contact_id => users.id)
#
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
    it { should belong_to(:point_of_contact).class_name('User').optional }
    it { should have_many(:owned_people).class_name('User').with_foreign_key(:point_of_contact_id) }
  end

  describe "#point_of_contact / #owned_people" do
    let(:operator) { create(:operator) }
    let(:gm) { create(:user, operator: operator, role: "general-manager") }
    let(:member) { create(:user, operator: operator, point_of_contact: gm) }

    it "links a person to their owner" do
      expect(member.point_of_contact).to eq(gm)
    end

    it "exposes owned_people from the owner" do
      member  # trigger let
      expect(gm.owned_people).to include(member)
    end

    it "allows a user with no point of contact" do
      orphan = create(:user, operator: operator)
      expect(orphan.point_of_contact).to be_nil
    end
  end

  describe "#assign_default_point_of_contact!" do
    let(:operator) { create(:operator) }
    let(:location) { create(:location, operator: operator) }
    let!(:gm) { create(:user, operator: operator, role: User::GENERAL_MANAGER, current_location: location) }
    let!(:admin) { create(:user, operator: operator, role: User::ADMIN, current_location: location) }

    it "assigns the location's general-manager when one exists" do
      member = create(:user, operator: operator, current_location: location, point_of_contact: nil)
      member.update_column(:point_of_contact_id, nil)  # in case after_create assigned
      member.assign_default_point_of_contact!
      expect(member.reload.point_of_contact).to eq(gm)
    end

    it "falls back to an admin when no GM at the location" do
      gm.update!(current_location: nil)
      member = create(:user, operator: operator, current_location: location)
      member.update_column(:point_of_contact_id, nil)
      member.assign_default_point_of_contact!
      expect(member.reload.point_of_contact).to eq(admin)
    end

    it "is a no-op when point_of_contact is already set" do
      other_gm = create(:user, operator: operator, role: User::GENERAL_MANAGER, current_location: location)
      member = create(:user, operator: operator, current_location: location)
      member.update!(point_of_contact: other_gm)
      member.assign_default_point_of_contact!
      expect(member.reload.point_of_contact).to eq(other_gm)
    end

    it "does not assign a PoC to staff users themselves" do
      new_gm = create(:user, operator: operator, role: User::GENERAL_MANAGER, current_location: location)
      expect(new_gm.point_of_contact).to be_nil
    end

    it "is a no-op when no GM and no admin exists" do
      gm.destroy
      admin.destroy
      member = create(:user, operator: operator, current_location: location)
      member.update_column(:point_of_contact_id, nil)
      expect { member.assign_default_point_of_contact! }.not_to raise_error
      expect(member.reload.point_of_contact).to be_nil
    end

    it "is a no-op when the user's operator record has been deleted (data-integrity orphan)" do
      member = create(:user, operator: operator, current_location: location)
      member.update_column(:point_of_contact_id, nil)
      # Simulate the prod scenario: operator_id still points to a now-missing
      # operator row (FKs don't ON DELETE CASCADE). #operator returns nil.
      allow(member).to receive(:operator).and_return(nil)
      expect { member.assign_default_point_of_contact! }.not_to raise_error
      expect(member.reload.point_of_contact).to be_nil
    end
  end

  describe "automatic point-of-contact assignment" do
    let(:operator) { create(:operator) }
    let(:location) { create(:location, operator: operator) }
    let!(:gm) { create(:user, operator: operator, role: User::GENERAL_MANAGER, current_location: location) }

    it "is set on User.after_create for new members" do
      member = create(:user, operator: operator, current_location: location)
      expect(member.point_of_contact).to eq(gm)
    end

    it "is set when a tour Activity is logged for a PoC-less user" do
      pocless = create(:user, operator: operator, current_location: nil)
      pocless.update_column(:point_of_contact_id, nil)
      pocless.update!(current_location: location)
      Activity.log(user: pocless, kind: :tour, operator: operator, subject: pocless)
      expect(pocless.reload.point_of_contact).to eq(gm)
    end

    it "is set when a Lead is created for a PoC-less user" do
      pocless = create(:user, operator: operator, current_location: nil)
      pocless.update_column(:point_of_contact_id, nil)
      pocless.update!(current_location: location)
      create(:lead, user: pocless, operator: operator)
      expect(pocless.reload.point_of_contact).to eq(gm)
    end

    it "does not overwrite an existing PoC when a tour Activity is logged" do
      other_gm = create(:user, operator: operator, role: User::GENERAL_MANAGER, current_location: location)
      member = create(:user, operator: operator, current_location: location, point_of_contact: other_gm)
      Activity.log(user: member, kind: :tour, operator: operator, subject: member)
      expect(member.reload.point_of_contact).to eq(other_gm)
    end
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

  describe "activity logging on signup" do
    let(:logged_operator) { create(:operator) }

    it "creates exactly one Activity of kind 'signup' on create" do
      expect {
        create(:user, operator: logged_operator, name: "New Person", email: "new@example.com")
      }.to change(Activity, :count).by(1)

      activity = Activity.last
      expect(activity.kind).to eq("signup")
      expect(activity.user).to eq(User.last)
      expect(activity.operator).to eq(logged_operator)
      expect(activity.subject).to eq(User.last)
    end

    it "denormalizes name and email into payload" do
      user = create(:user, operator: logged_operator, name: "New Person", email: "new@example.com")
      payload = Activity.where(subject: user).last.payload

      expect(payload["name"]).to eq("New Person")
      expect(payload["email"]).to eq("new@example.com")
    end
  end

  describe "#lifecycle_stage" do
    let(:stage_operator) { create(:operator) }
    let(:stage_location) { create(:location, operator: stage_operator) }
    let(:stage_user) { create(:user, operator: stage_operator, current_location: stage_location) }

    def log_activity(user, kind, occurred_at)
      Activity.create!(user: user, operator: user.operator, kind: kind,
                       occurred_at: occurred_at, subject: user)
    end

    context "with an active subscription" do
      before { create(:subscription, subscribable: stage_user, billable: stage_user, active: true) }

      it "returns :member" do
        expect(stage_user.lifecycle_stage).to eq(:member)
      end

      it "returns :member even when a Lead row exists" do
        create(:lead, user: stage_user, operator: stage_operator)
        expect(stage_user.lifecycle_stage).to eq(:member)
      end

      it "returns :member even when the user has a recent day pass" do
        create(:day_pass, user: stage_user, billable: stage_user,
               operator: stage_operator, location: stage_location,
               day: 5.days.ago.to_date)
        expect(stage_user.lifecycle_stage).to eq(:member)
      end
    end

    context "with subscription ended within the grace window" do
      before do
        log_activity(stage_user, "subscription_ended",
                     (User::DEFAULT_PAST_MEMBER_GRACE_DAYS - 5).days.ago)
      end

      it "returns :member (still in grace)" do
        expect(stage_user.lifecycle_stage).to eq(:member)
      end
    end

    context "with subscription ended past the grace window" do
      before do
        log_activity(stage_user, "subscription_ended",
                     (User::DEFAULT_PAST_MEMBER_GRACE_DAYS + 5).days.ago)
      end

      it "returns :past_member" do
        expect(stage_user.lifecycle_stage).to eq(:past_member)
      end
    end

    context "with a custom per-location grace window" do
      before do
        stage_location.update!(past_member_grace_days: 300)
      end

      it "treats subscription_ended 250 days ago as still :member (within 300-day grace)" do
        log_activity(stage_user, "subscription_ended", 250.days.ago)
        expect(stage_user.lifecycle_stage).to eq(:member)
      end

      it "treats subscription_ended 310 days ago as :past_member (past 300-day grace)" do
        log_activity(stage_user, "subscription_ended", 310.days.ago)
        expect(stage_user.lifecycle_stage).to eq(:past_member)
      end
    end

    context "user with no current_location" do
      let(:stage_user) { create(:user, operator: stage_operator, current_location: nil) }

      it "falls back to DEFAULT_PAST_MEMBER_GRACE_DAYS" do
        log_activity(stage_user, "subscription_ended",
                     (User::DEFAULT_PAST_MEMBER_GRACE_DAYS - 5).days.ago)
        expect(stage_user.lifecycle_stage).to eq(:member)
      end
    end

    context "with a day pass in the last 30 days and no active subscription" do
      before do
        create(:day_pass, user: stage_user, billable: stage_user,
               operator: stage_operator, location: stage_location,
               day: 10.days.ago.to_date)
      end

      it "returns :day_passer" do
        expect(stage_user.lifecycle_stage).to eq(:day_passer)
      end
    end

    context "with a recent day pass and a long-expired subscription" do
      before do
        log_activity(stage_user, "subscription_ended",
                     (User::DEFAULT_PAST_MEMBER_GRACE_DAYS + 30).days.ago)
        create(:day_pass, user: stage_user, billable: stage_user,
               operator: stage_operator, location: stage_location,
               day: 5.days.ago.to_date)
      end

      it "returns :day_passer (recent day pass beats past membership)" do
        expect(stage_user.lifecycle_stage).to eq(:day_passer)
      end
    end

    context "previously active, no recent visits, no recent day pass" do
      before do
        log_activity(stage_user, "checkin", 60.days.ago)
      end

      it "returns :quiet" do
        expect(stage_user.lifecycle_stage).to eq(:quiet)
      end
    end

    context "previously active with a checkin within the last 30 days" do
      before do
        log_activity(stage_user, "checkin", 60.days.ago)
        log_activity(stage_user, "checkin", 5.days.ago)
      end

      it "does not return :quiet" do
        expect(stage_user.lifecycle_stage).not_to eq(:quiet)
      end
    end

    context "with a Lead row but no tour Activity" do
      before { create(:lead, user: stage_user, operator: stage_operator) }

      it "returns :signup_only (a Lead alone doesn't make them a tour-taker)" do
        expect(stage_user.lifecycle_stage).to eq(:signup_only)
      end
    end

    context "with a tour Activity but no Lead" do
      before { log_activity(stage_user, "tour", 7.days.ago) }

      it "returns :tour_taker (tour Activity is the trigger)" do
        expect(stage_user.lifecycle_stage).to eq(:tour_taker)
      end
    end

    context "with no other state" do
      it "returns :signup_only as the catch-all (was :tour_taker before refinement)" do
        expect(stage_user.lifecycle_stage).to eq(:signup_only)
      end
    end
  end

  describe ".in_stage" do
    let(:stage_operator) { create(:operator) }
    let(:stage_location) { create(:location, operator: stage_operator) }

    def user_in(operator, current_location:)
      create(:user, operator: operator, current_location: current_location)
    end

    def log_activity(user, kind, occurred_at)
      Activity.create!(user: user, operator: user.operator, kind: kind,
                       occurred_at: occurred_at, subject: user)
    end

    let!(:member) do
      u = user_in(stage_operator, current_location: stage_location)
      create(:subscription, subscribable: u, billable: u, active: true)
      u
    end

    let!(:past_member) do
      u = user_in(stage_operator, current_location: stage_location)
      log_activity(u, "subscription_ended", (User::DEFAULT_PAST_MEMBER_GRACE_DAYS + 10).days.ago)
      u
    end

    let!(:day_passer) do
      u = user_in(stage_operator, current_location: stage_location)
      create(:day_pass, user: u, billable: u, operator: stage_operator,
             location: stage_location, day: 5.days.ago.to_date)
      u
    end

    let!(:quiet_user) do
      u = user_in(stage_operator, current_location: stage_location)
      log_activity(u, "checkin", 60.days.ago)
      u
    end

    let!(:tour_taker) do
      u = user_in(stage_operator, current_location: stage_location)
      log_activity(u, "tour", 5.days.ago)
      u
    end

    let!(:signup_only_user) do
      # Signed up, never engaged, never had a tour logged
      user_in(stage_operator, current_location: stage_location)
    end

    it "returns users in :member stage" do
      expect(User.in_stage(:member)).to contain_exactly(member)
    end

    it "returns users in :past_member stage" do
      expect(User.in_stage(:past_member)).to contain_exactly(past_member)
    end

    it "returns users in :day_passer stage" do
      expect(User.in_stage(:day_passer)).to contain_exactly(day_passer)
    end

    it "returns users in :quiet stage" do
      expect(User.in_stage(:quiet)).to contain_exactly(quiet_user)
    end

    it "returns users in :tour_taker stage (only those with a tour Activity)" do
      expect(User.in_stage(:tour_taker)).to contain_exactly(tour_taker)
    end

    it "returns users in :signup_only stage (catch-all for signups with no engagement and no tour)" do
      expect(User.in_stage(:signup_only)).to contain_exactly(signup_only_user)
    end

    it "is consistent with #lifecycle_stage for each user" do
      [member, past_member, day_passer, quiet_user, tour_taker, signup_only_user].each do |u|
        expect(User.in_stage(u.lifecycle_stage)).to include(u)
      end
    end

    context "with a custom per-location grace window" do
      let!(:custom_location) do
        create(:location, operator: stage_operator, past_member_grace_days: 300)
      end

      let!(:still_member_on_custom_location) do
        u = create(:user, operator: stage_operator, current_location: custom_location)
        log_activity(u, "subscription_ended", 250.days.ago)
        u
      end

      it "classifies the 250-days-ago-ended user as :member (within 300-day grace)" do
        expect(User.in_stage(:member)).to include(still_member_on_custom_location)
        expect(User.in_stage(:past_member)).not_to include(still_member_on_custom_location)
      end
    end
  end

  describe "#enroll_in_welcome_drip!" do
    let(:wd_operator) { create(:operator) }
    let(:wd_location) { create(:location, operator: wd_operator) }
    let(:wd_user) { create(:user, operator: wd_operator, current_location: wd_location) }

    it "creates a welcome_drip_enrolled marker and returns true" do
      expect(wd_user.enroll_in_welcome_drip!).to be true
      expect(wd_user.welcome_drip_enrolled?).to be true
    end

    it "is idempotent (re-enrolling returns false and does not duplicate)" do
      wd_user.enroll_in_welcome_drip!
      expect {
        expect(wd_user.enroll_in_welcome_drip!).to be false
      }.not_to change { ProductEmailSend.where(sendable: wd_user, email_type: "welcome_drip_enrolled").count }
    end

    it "is a no-op for users with an active subscription" do
      # Force the active-subscription check to be true without wiring up the
      # full Subscription factory (which routes through Cowork Tahoe fixture).
      allow(wd_user).to receive(:has_active_subscription?).and_return(true)
      expect(wd_user.enroll_in_welcome_drip!).to be false
      expect(wd_user.welcome_drip_enrolled?).to be false
    end

    it "enrolls the user even when a recent transactional email_sent exists" do
      # Per David: system / transactional emails (e.g. account confirmation
      # at signup, day-pass receipts) must NOT block welcome-drip enrollment.
      # SpamGuard's 30-day cool-down still applies to *other* drip campaigns
      # and one-off sends — just not to the foundational welcome drip.
      Activity.create!(
        user: wd_user, operator: wd_operator,
        kind: "email_sent",
        subject: wd_user,
        occurred_at: 5.minutes.ago,
        payload: { "subject" => "Confirm your email for #{wd_operator.name}",
                   "mailer" => "UserMailer", "action" => "email_confirmation" },
      )

      expect(wd_user.enroll_in_welcome_drip!).to be true
      expect(wd_user.welcome_drip_enrolled?).to be true
    end

    it "still refuses enrollment when the user is already in an active drip campaign" do
      # The 'one active series at a time' invariant from ADR-0003 stays — the
      # welcome drip exemption is from the recently-emailed cool-down only.
      allow(SpamGuard).to receive(:in_active_drip?).with(wd_user, wd_operator).and_return(true)
      expect(wd_user.enroll_in_welcome_drip!).to be false
      expect(wd_user.welcome_drip_enrolled?).to be false
    end
  end

  describe "DayPass.after_create welcome-drip enrollment" do
    let(:wd_operator) { create(:operator) }
    let(:wd_location) { create(:location, operator: wd_operator) }
    let(:wd_user) { create(:user, operator: wd_operator, current_location: wd_location) }

    it "enrolls the user in the welcome drip when a day pass is created" do
      expect {
        create(:day_pass, user: wd_user, billable: wd_user, operator: wd_operator,
                          location: wd_location, day: Date.current)
      }.to change { wd_user.reload.welcome_drip_enrolled? }.from(false).to(true)
    end

    it "is idempotent (a second day pass does not re-enroll)" do
      create(:day_pass, user: wd_user, billable: wd_user, operator: wd_operator,
                        location: wd_location, day: Date.current)
      expect {
        create(:day_pass, user: wd_user, billable: wd_user, operator: wd_operator,
                          location: wd_location, day: 1.day.ago.to_date)
      }.not_to change { ProductEmailSend.where(sendable: wd_user, email_type: "welcome_drip_enrolled").count }
    end
  end

  describe "#subscription_reservation_charge_info — paid-room guard" do
    # Mirror of day_pass_reservation_charge_info's guard: a paid room
    # (hourly_rate_in_cents > 0) must not trigger subscription overage.
    let(:prod_operator) { create(:operator, billing_state: "production") }
    let(:prod_location) { create(:location, operator: prod_operator) }
    let(:metered_plan) do
      create(:plan,
        operator: prod_operator,
        location: prod_location,
        included_meeting_room_minutes: 60,
        overage_rate_in_cents: 10)
    end
    let(:member_user) { create(:user, operator: prod_operator) }
    let!(:subscription) do
      create(:subscription,
        subscribable: member_user,
        billable: member_user,
        plan: metered_plan,
        active: true,
        paused: false,
        start_date: 1.month.ago.to_date)
    end
    let(:paid_room) { create(:room, operator: prod_operator, location: prod_location, hourly_rate_in_cents: 2000) }

    it "returns nil for a paid room even when the pool is exhausted (no overage added)" do
      result = member_user.subscription_reservation_charge_info(prod_location, 120, room: paid_room)
      expect(result).to be_nil
    end
  end

  # The day-pass quote must agree with ChargeCalculator (ADR 0012): both read
  # the overage RATE from the LOCATION, so the hold placed at booking matches
  # the amount captured at settle. The day-pass type still defines the included
  # minutes; only the rate moved up to the location.
  describe "#day_pass_reservation_charge_info — overage priced from the LOCATION rate" do
    let(:prod_operator) { create(:operator, billing_state: "production") }
    # $12/hr = 20¢/min on the location; the day-pass type's rate is stale and ignored.
    let(:prod_location) { create(:location, operator: prod_operator, overage_rate_in_cents: 1200) }
    let(:dp_user) { create(:user, operator: prod_operator) }
    let(:call_room) { create(:room, operator: prod_operator, location: prod_location, hourly_rate_in_cents: 0) }
    let!(:day_pass) do
      dpt = create(:day_pass_type, operator: prod_operator, location: prod_location,
                                   included_meeting_room_minutes: 60, overage_rate_in_cents: 9999)
      create(:day_pass, user: dp_user, billable: dp_user, operator: prod_operator,
                        location: prod_location, day_pass_type: dpt, day: Date.current)
    end

    it "prices the over-minutes at the location rate, not the day-pass-type rate" do
      info = dp_user.day_pass_reservation_charge_info(prod_location, Date.current, 90, room: call_room)
      expect(info[:charge_type]).to eq(:partial_overage)
      expect(info[:overage_amount_in_cents]).to eq(600) # 30 over-min × 20¢
      expect(info[:overage_rate_in_cents]).to eq(1200)
    end
  end

end
