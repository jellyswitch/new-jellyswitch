require 'rails_helper'

RSpec.describe 'New member buys day pass', type: :system, js: true do
  let(:subdomain) { create(:subdomain) }
  let(:operator) { create(:operator, :with_day_passes, subdomain: subdomain.subdomain) }
  let(:admin_user) { create(:user, :admin, operator: operator) }

  before do
    ActsAsTenant.default_tenant = operator
  end

  after do
    ActsAsTenant.default_tenant = nil
  end

  context 'paying with card' do
    it 'allows a user to purchase a day pass' do
      new_member_session do |new_member|
        new_member.sign_up
        new_member.choose_day_pass
        new_member.add_card
        new_member.wait_for_approval
      end

      admin_session do |admin|
        admin.sign_in
        admin.approve_member
      end

      new_member_session do |new_member|
        new_member.refresh

        expect(page).to have_content 'Building Access'
      end
    end
  end

  context 'paying by check' do
    it 'allows a user to purchase a day pass' do
      new_member_session do |new_member|
        new_member.sign_up
        new_member.choose_day_pass
        new_member.select_pay_out_of_band
        new_member.wait_for_approval
      end

      admin_session do |admin|
        admin.sign_in
        admin.approve_member
      end

      new_member_session do |new_member|
        new_member.refresh

        expect(page).to have_content 'Building Access'
      end
    end
  end
end
