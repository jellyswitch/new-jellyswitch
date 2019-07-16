# typed: false
require 'rails_helper'

RSpec.describe 'Authentication', type: :request do
  context "for an admin" do
    let(:subdomain) { create(:subdomain) }
    let(:admin) { create(:user, :admin) }
    let(:operator) { create(:operator, :with_location, :with_individual_plans, subdomain: subdomain.subdomain) }

    before do
      ActsAsTenant.default_tenant = operator
    end

    after do
      ActsAsTenant.default_tenant = nil
    end

    it "redirects to the management feed with a correct password" do
      post login_path, params: { session: { email: admin.email, password: 'password' } }
      puts response.inspect
      expect(response).to redirect_to(feed_items_path)
    end

    it "re-renders the login page with an incorrect password"
  end

  context "for a superadmin"
  context "for a member"
end